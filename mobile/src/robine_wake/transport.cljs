(ns robine-wake.transport
  (:require [clojure.string :as str]
            [robine-wake.protocol :as protocol]
            [robine-wake.sse :as sse]
            [robine-wake.store :as store]
            ["@react-native-async-storage/async-storage" :default AsyncStorage]
            ["expo/fetch" :refer [fetch]]
            ["react-native" :refer [AppState Platform Settings]]
            ["react-native-ble-plx" :refer [BleManager]]))

(def service-uuid "8AD00001-A7A9-4EF7-A259-67C9C65E4C10")
(def command-uuid "8AD00002-A7A9-4EF7-A259-67C9C65E4C10")
(def response-uuid "8AD00003-A7A9-4EF7-A259-67C9C65E4C10")
(def endpoint-storage-key "robineWake.httpCommandEndpoint.v1")
(def web? (= "web" (.-OS Platform)))
(def web-command-endpoint "/api/v1/command")

(defonce manager (when-not web? (BleManager.)))
(defonce connected-device (atom nil))
(defonce pending-command (atom nil))
(defonce bluetooth-state-subscription (atom nil))
(defonce event-controller (atom nil))
(defonce event-retry-timer (atom nil))
(defonce event-retry-delay (atom 1000))
(defonce event-generation (atom 0))
(defonce event-last-id (atom nil))
(defonce event-endpoint (atom nil))
(defonce event-refresh-pending? (atom false))
(defonce app-state-subscription (atom nil))

(def error-messages
  {"stale_revision" "Cette alarme a changé. Actualisez avant de réessayer."
   "not_found" "Cet élément n’existe plus sur le réveil."
   "validation_failed" "Certains réglages ne sont pas valides."
   "hue_link_button_required" "Appuyez sur le bouton rond du pont Hue, puis réessayez."
   "invalid_hue_bridge_address" "L’adresse du pont Hue n’est pas valide."
   "hue_pairing_failed" "Le pont Hue a refusé l’association."
   "hue_target_not_found" "Cette pièce ou zone Hue n’est plus disponible."
   "wake_session_active" "Une alarme utilise déjà la lumière Hue."
   "unsupported_operation" "Cette fonction nécessite une version plus récente du réveil."
   "pairing_window_closed" "La fenêtre d’association du bouton est fermée."
   "remote_button_not_paired" "Ce bouton n’est plus associé au réveil."})

(defn make-request-id []
  (str/lower-case (str (random-uuid))))

(defn expo-fetch! [url options]
  ;; On web, expo/fetch delegates to Window.fetch, which must keep its receiver.
  (.call fetch js/globalThis url options))

(defn response-pages! [^js device]
  (letfn [(read-next [acc expected-index metadata]
            (-> (.readCharacteristicForService device service-uuid response-uuid)
                (.then
                 (fn [characteristic]
                   (let [page (protocol/parse-page (.-value characteristic))
                         expected (or metadata (select-keys page [:sequence :count :total :crc]))]
                     (when (or (not= expected-index (:index page))
                               (not= expected (select-keys page [:sequence :count :total :crc]))
                               (zero? (:count page))
                               (> (:total page) 1048576))
                       (throw (js/Error. "Pages Bluetooth incohérentes")))
                     (let [assembled (protocol/concat-bytes acc (:payload page))]
                       (if (:final? page)
                         (do
                           (when (or (not= (inc expected-index) (:count page))
                                     (not= (.-length assembled) (:total page))
                                     (not= (protocol/crc32 assembled) (:crc page)))
                             (throw (js/Error. "Réponse Bluetooth incomplète ou corrompue")))
                           (protocol/bytes->string assembled))
                         (read-next assembled (inc expected-index) expected))))))))]
    (read-next (js/Uint8Array. 0) 0 nil)))

(defn write-chunks! [^js device payload]
  (let [bytes (protocol/utf8-bytes (str payload "\n"))
        chunks (map #(.slice bytes % (min (.-length bytes) (+ % 180)))
                    (range 0 (.-length bytes) 180))]
    (reduce (fn [promise chunk]
              (.then promise
                     (fn []
                       (.writeCharacteristicWithResponseForService
                        device service-uuid command-uuid (protocol/bytes->base64 chunk)))))
            (js/Promise.resolve)
            chunks)))

(defn ble-request! [json]
  (if-let [device @connected-device]
    (-> (write-chunks! device json)
        (.then #(response-pages! device)))
    (js/Promise.reject (js/Error. "Bluetooth indisponible"))))

(defn http-request! [endpoint json]
  (-> (expo-fetch! endpoint
                   #js {:method "POST"
                        :headers #js {"Content-Type" "application/json" "Accept" "application/json"}
                        :body json})
      (.then (fn [response]
               (if (.-ok response)
                 (.text response)
                 (throw (js/Error. "Le réveil a refusé la connexion Wi-Fi")))))))

(declare command! refresh! start-event-stream! stop-event-stream! drain-event-refresh!)

(defn remember-endpoint! [body]
  (when-not web?
    (when-let [endpoint (first (get-in body [:transport :http_endpoints]))]
      (let [changed? (not= endpoint (:http-endpoint @store/app-state))]
        (store/set-state! :http-endpoint endpoint)
        (.setItem AsyncStorage endpoint-storage-key endpoint)
        (when changed? (start-event-stream! endpoint))))))

(defn apply-state! [body]
  (remember-endpoint! body)
  (store/merge-state!
   {:alarms (vec (sort-by :local_time (:alarms body)))
    :sounds (vec (:sounds body))
    :device (:device body)
    :recent-sessions (vec (:recent_sessions body))
    :active-session (:active_session body)
    :hue (:hue body)
    :hue-targets (vec (:hue_targets body))
    :remote-button (:remote_button body)
    :breathing-synchronized-at (when (get-in body [:hue :breathing :active]) (js/Date.))
    :last-updated (js/Date.)}))

(defn handle-response! [operation request-id text]
  (let [envelope (js->clj (js/JSON.parse text) :keywordize-keys true)]
    (when-not (= 1 (:v envelope))
      (throw (js/Error. "Version du protocole non prise en charge")))
    (when-not (= request-id (:id envelope))
      (throw (js/Error. "La réponse ne correspond pas à la commande")))
    (when-not (= "ok" (:status envelope))
      (let [code (get-in envelope [:error :code])]
        (throw (js/Error. (or (get error-messages code)
                             (str "Le réveil a refusé la commande (" code ")"))))))
    (case operation
      "state.get" (apply-state! (:body envelope))
      "session.get" (store/set-state! :active-session (get-in envelope [:body :active_session]))
      nil)
    (:body envelope)))

(defn finish-command! []
  (reset! pending-command nil)
  (store/set-state! :busy? false)
  (drain-event-refresh!))

(defn command!
  ([operation] (command! operation {}))
  ([operation body]
   (if @pending-command
     (js/Promise.reject (js/Error. "Une synchronisation est déjà en cours"))
     (let [request-id (make-request-id)
           request (js/JSON.stringify
                    (clj->js {:v 1 :id request-id :op operation :body body}))
           endpoint (:http-endpoint @store/app-state)]
       (reset! pending-command operation)
       (store/merge-state! {:busy? true :error nil})
       (-> (if endpoint
             (-> (http-request! endpoint request)
                 (.then (fn [value]
                          (store/merge-state! {:transport :http :connection :connected})
                          value))
                 (.catch (fn [error]
                           (if web?
                             (js/Promise.reject error)
                             (do
                               (stop-event-stream!)
                               (.removeItem AsyncStorage endpoint-storage-key)
                               (store/set-state! :http-endpoint nil)
                               (ble-request! request))))))
             (ble-request! request))
           (.then #(handle-response! operation request-id %))
           (.then (fn [response]
                    (when-not (#{"state.get" "session.get"} operation)
                      (reset! event-refresh-pending? true))
                    (finish-command!)
                    response))
           (.catch (fn [error]
                     (finish-command!)
                     (store/set-state! :error (or (.-message error) "Connexion au réveil impossible"))
                     (throw error))))))))

(defn refresh! []
  (if-not @pending-command
    (command! "state.get")
    (js/Promise.resolve nil)))

(defn drain-event-refresh! []
  (when (and @event-refresh-pending? (not @pending-command))
    (reset! event-refresh-pending? false)
    (-> (refresh!) (.catch (fn [_] nil)))))

(defn request-event-refresh! []
  (reset! event-refresh-pending? true)
  (drain-event-refresh!))

(defn clear-event-retry! []
  (when-let [timer @event-retry-timer]
    (js/clearTimeout timer)
    (reset! event-retry-timer nil)))

(defn stop-event-stream! []
  (swap! event-generation inc)
  (clear-event-retry!)
  (when-let [controller @event-controller]
    (.abort controller)
    (reset! event-controller nil)))

(defn event-stream-active? []
  (or web? (not (#{"background" "inactive"} (.-currentState AppState)))))

(defn handle-event! [{:keys [id event data]}]
  ;; The server sends "ready" before replaying missed events, so it must not
  ;; advance our resume cursor until those replay events have been consumed.
  (when (and id (not= event "ready")) (reset! event-last-id id))
  (when (= event "ready")
    (reset! event-retry-delay 1000)
    (store/merge-state! {:transport :http :connection :connected}))
  (when (#{"state.changed" "session.changed" "breathing.changed"} event)
    (try
      (let [envelope (js->clj (js/JSON.parse data) :keywordize-keys true)]
        (when (= 1 (:v envelope)) (request-event-refresh!)))
      (catch :default _ nil))))

(defn read-event-stream! [response generation]
  (when-not (.-ok response)
    (throw (js/Error. "Le flux temps réel du réveil est indisponible")))
  (when-not (.-body response)
    (throw (js/Error. "Le flux temps réel n’est pas pris en charge")))
  (store/merge-state! {:transport :http :connection :connected})
  (reset! event-retry-delay 1000)
  (let [reader (.getReader (.-body response))
        decoder (js/TextDecoder.)
        buffer (atom "")]
    (letfn [(read-next []
              (-> (.read reader)
                  (.then
                   (fn [result]
                     (when (= generation @event-generation)
                       (if (.-done result)
                         (throw (js/Error. "Le flux temps réel a été interrompu"))
                         (let [{:keys [events]
                                next-buffer :buffer}
                               (sse/consume-chunk
                                @buffer
                                (.decode decoder (.-value result) #js {:stream true}))]
                           (reset! buffer next-buffer)
                           (doseq [event events] (handle-event! event))
                           (read-next))))))))]
      (read-next))))

(defn schedule-event-reconnect! [command-endpoint generation]
  (when (and (= generation @event-generation) (event-stream-active?))
    (let [delay @event-retry-delay]
      (reset! event-retry-delay (min 15000 (* 2 delay)))
      (clear-event-retry!)
      (reset! event-retry-timer
              (js/setTimeout
               (fn []
                 (reset! event-retry-timer nil)
                 (when (= generation @event-generation)
                   (start-event-stream! command-endpoint)))
               delay)))))

(defn start-event-stream! [command-endpoint]
  (when (and (not (str/blank? command-endpoint)) (event-stream-active?))
    (let [next-endpoint (sse/events-endpoint command-endpoint)
          same-endpoint? (= next-endpoint @event-endpoint)]
      (stop-event-stream!)
      (when-not same-endpoint? (reset! event-last-id nil))
      (reset! event-endpoint next-endpoint)
      (let [generation @event-generation
            controller (js/AbortController.)
            headers (cond-> {"Accept" "text/event-stream"
                             "Cache-Control" "no-cache"}
                      @event-last-id (assoc "Last-Event-ID" @event-last-id))]
        (reset! event-controller controller)
        (-> (expo-fetch! next-endpoint
                        (clj->js {:method "GET"
                                  :headers headers
                                  :signal (.-signal controller)}))
            (.then #(read-event-stream! % generation))
            (.catch
             (fn [error]
               (when (and (= generation @event-generation)
                          (not= "AbortError" (.-name error)))
                 (reset! event-controller nil)
                 (schedule-event-reconnect! command-endpoint generation)))))))))

(defn install-app-state-listener! []
  (when-not web?
    (when-let [subscription @app-state-subscription] (.remove subscription))
    (reset! app-state-subscription
            (.addEventListener
             AppState "change"
             (fn [state]
               (if (= state "active")
                 (when-let [endpoint (:http-endpoint @store/app-state)]
                   (start-event-stream! endpoint)
                   (-> (refresh!) (.catch (fn [_] nil))))
                 (stop-event-stream!)))))))

(defn connect-device! [^js device]
  (.stopDeviceScan manager)
  (store/set-state! :connection :connecting)
  (-> (.connect device)
      (.then (fn [^js connected] (.discoverAllServicesAndCharacteristics connected)))
      (.then (fn [ready]
               (reset! connected-device ready)
               (store/merge-state! {:connection :connected :transport :bluetooth})
               (refresh!)))
      (.catch (fn [error]
                (reset! connected-device nil)
                (store/merge-state! {:connection :disconnected
                                     :error (or (.-message error) "Connexion Bluetooth impossible")})))))

(defn stop-state-listener! []
  (when-let [subscription @bluetooth-state-subscription]
    (.remove subscription)
    (reset! bluetooth-state-subscription nil)))

(defn begin-scan! []
  (stop-state-listener!)
  (.stopDeviceScan manager)
  (.startDeviceScan
   manager (clj->js [service-uuid]) nil
   (fn [error device]
     (cond
       error (store/merge-state! {:connection :disconnected :error (.-message error)})
       device (connect-device! device)))))

(defn scan! []
  (store/merge-state! {:connection :scanning :error nil})
  (.stopDeviceScan manager)
  (stop-state-listener!)
  (reset! bluetooth-state-subscription
          (.onStateChange
           manager
           (fn [state]
             (case state
               "PoweredOn" (begin-scan!)
               "Unauthorized" (do
                                (stop-state-listener!)
                                (store/merge-state!
                                 {:connection :disconnected
                                  :error "Autorisez le Bluetooth dans Réglages pour joindre le réveil."}))
               "Unsupported" (do
                               (stop-state-listener!)
                               (store/merge-state!
                                {:connection :disconnected :error nil}))
               "PoweredOff" (store/merge-state! {:connection :disconnected :error nil})
               nil))
           true)))

(defn load-endpoint! []
  (-> (.getItem AsyncStorage endpoint-storage-key)
      (.then
       (fn [endpoint]
         (if-not (str/blank? endpoint)
           endpoint
           (let [legacy-endpoint (when Settings (.get Settings endpoint-storage-key))]
             (when (and (string? legacy-endpoint) (not (str/blank? legacy-endpoint)))
               (.setItem AsyncStorage endpoint-storage-key legacy-endpoint)
               legacy-endpoint)))))))

(defn start! []
  (install-app-state-listener!)
  (if web?
    (do
      (store/merge-state! {:http-endpoint web-command-endpoint
                           :transport :http
                           :connection :connecting})
      (start-event-stream! web-command-endpoint)
      (-> (refresh!) (.catch (fn [_] nil))))
    (-> (load-endpoint!)
        (.then (fn [endpoint]
                 (if endpoint
                   (do (store/set-state! :http-endpoint endpoint)
                       (start-event-stream! endpoint)
                       (-> (refresh!) (.catch (fn [_] (scan!)))))
                   (scan!)))))))

(defn reconnect! []
  (if web?
    (do
      (store/merge-state! {:http-endpoint web-command-endpoint
                           :transport :http
                           :connection :connecting})
      (start-event-stream! web-command-endpoint)
      (refresh!))
    (do
      (stop-event-stream!)
      (reset! connected-device nil)
      (scan!))))
