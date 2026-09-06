(ns robine-wake.app
  (:require [reagent.core :as r]
            [shadow.expo :as expo]
            [robine-wake.actions :as actions]
            [robine-wake.challenge :refer [wake-challenge]]
            [robine-wake.editor :refer [alarm-editor]]
            [robine-wake.routes :as routes]
            [robine-wake.screens :as screens]
            [robine-wake.store :as store]
            [robine-wake.theme :as theme]
            [robine-wake.transport :as transport]
            ["react-native" :as rn]
            ["react-native-safe-area-context" :refer [SafeAreaProvider SafeAreaView]]
            ["expo-status-bar" :refer [StatusBar]]))

(def View (.-View rn))
(def Text (.-Text rn))
(def Pressable (.-Pressable rn))
(def Modal (.-Modal rn))
(def Platform (.-Platform rn))
(def web? (= "web" (.-OS Platform)))
(defonce popstate-handler (atom nil))

(def tabs
  [{:id :morning :label "Matin" :icon "sunny"}
   {:id :evening :label "Soir" :icon "moon"}
   {:id :alarms :label "Alarmes" :icon "alarm"}
   {:id :system :label "Réveil" :icon "sparkles"}])

(defn apply-tab! [tab]
  (store/set-state! :tab tab)
  (when web?
    (set! (.-title js/document) (routes/title-for-tab tab))))

(defn navigate! [tab]
  (when web?
    (let [path (routes/path-for-tab tab)]
      (when (not= path (.-pathname js/location))
        (.pushState js/history #js {:tab (name tab)} "" path))
      (.scrollTo js/window #js {:top 0 :behavior "smooth"})))
  (apply-tab! tab))

(defn route-press! [tab ^js event]
  (if web?
    (let [^js native-event (.-nativeEvent event)
          modified? (or (.-altKey native-event)
                        (.-ctrlKey native-event)
                        (.-metaKey native-event)
                        (.-shiftKey native-event)
                        (not= 0 (or (.-button native-event) 0)))]
      (when-not modified?
        (.preventDefault event)
        (navigate! tab)))
    (navigate! tab)))

(defn apply-browser-route! []
  (when web?
    (when-let [tab (routes/tab-for-path (.-pathname js/location))]
      (apply-tab! tab))))

(defn install-browser-routing! []
  (when web?
    (when-let [handler @popstate-handler]
      (.removeEventListener js/window "popstate" handler))
    (let [handler (fn [_] (apply-browser-route!))]
      (reset! popstate-handler handler)
      (.addEventListener js/window "popstate" handler))
    (apply-browser-route!)))

(defn tab-bar []
  (let [state @store/app-state]
    [theme/glass-panel
     {:effect "regular" :interactive? true :tint "rgba(30,20,37,0.7)"
      :fallback-background "rgba(24,16,28,0.98)"
      :style {:position "absolute" :left 10 :right 10 :bottom 8
              :height 82 :padding-top 8 :padding-bottom 18 :padding-horizontal 5
              :flex-direction "row" :border-radius 29
              :border-width 1 :border-color "rgba(255,231,183,0.16)"
              :shadow-color "#000" :shadow-opacity 0.38 :shadow-radius 24
              :shadow-offset {:width 0 :height 10}}}
     (for [{:keys [id label icon]} tabs]
       (let [active? (= id (:tab state))]
         ^{:key (name id)}
         [:> Pressable {:accessibilityRole (if web? "link" "button")
                        :href (when web? (routes/path-for-tab id))
                        :onPress #(route-press! id %)
                        :style (theme/js-style {:flex 1 :align-items "center" :justify-content "center"
                                                :gap 3 :border-radius 20
                                                :background-color (when active? "rgba(245,207,135,0.13)")})}
          [theme/icon icon 22 (if active? :moon :muted)]
          [:> Text {:style (theme/js-style {:font-size 10 :font-weight "750"
                                            :color (theme/c (if active? :moon :muted))})}
           label]]))]))

(defn desktop-sidebar []
  (let [state @store/app-state]
    [:> View {:style (theme/js-style {:width 256 :padding-horizontal 20 :padding-vertical 28
                                      :background-color "rgba(20,14,25,0.76)"
                                      :border-right-width 1 :border-right-color "rgba(255,231,183,0.09)"})}
     [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 12
                                       :padding-horizontal 8 :margin-bottom 34})}
      [theme/crescent 34]
      [:> View
       [:> Text {:style (theme/js-style {:font-size 13 :font-weight "900" :letter-spacing 1.7
                                         :color (theme/c :text)})} "ROBINE WAKE"]
       [:> Text {:style (theme/js-style {:font-size 11 :margin-top 2 :color (theme/c :muted)})}
        "Des matins plus doux"]]]
     [theme/eyebrow "Vos rituels" :moon]
     [:> View {:style (theme/js-style {:gap 8 :margin-top 12})}
      (for [{:keys [id label icon]} tabs]
        (let [active? (= id (:tab state))]
          ^{:key (name id)}
          [:> Pressable {:accessibilityRole (if web? "link" "button")
                         :href (when web? (routes/path-for-tab id))
                         :onPress #(route-press! id %)
                         :style (fn [press-state]
                                  (theme/js-style {:height 48 :padding-horizontal 14 :border-radius 15
                                                   :flex-direction "row" :align-items "center" :gap 12
                                                   :cursor "pointer"
                                                   :background-color (cond
                                                                       (.-pressed press-state) "rgba(245,207,135,0.18)"
                                                                       active? "rgba(245,207,135,0.13)"
                                                                       :else "transparent")
                                                   :border-width 1
                                                   :border-color (if active?
                                                                   "rgba(245,207,135,0.24)" "transparent")}))}
           [theme/icon icon 21 (if active? :moon :muted)]
           [:> Text {:style (theme/js-style {:font-size 14 :font-weight (if active? "800" "650")
                                             :color (theme/c (if active? :text :muted))})} label]
           (when active? [:> View {:style (theme/js-style {:margin-left "auto" :width 6 :height 6
                                                            :border-radius 3 :background-color (theme/c :moon)})}])]))]
     [:> View {:style (theme/js-style {:flex 1})}]
     [:> View {:style (theme/js-style {:padding 15 :border-radius 18
                                       :background-color "rgba(245,207,135,0.055)"
                                       :border-width 1 :border-color "rgba(245,207,135,0.12)"})}
      [:> Text {:style (theme/js-style {:font-size 11 :font-weight "800" :color (theme/c :muted)})}
       "LE RÉVEIL VEILLE"]
      [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 8 :margin-top 9})}
       [:> View {:style (theme/js-style {:width 8 :height 8 :border-radius 4
                                         :background-color (theme/c (if (:http-endpoint state) :mint :rose))})}]
       [:> Text {:style (theme/js-style {:font-size 13 :font-weight "700" :color (theme/c :text)})}
        (if (:http-endpoint state) "Tout est prêt pour demain" "Connexion à retrouver")]]
      [:> Text {:style (theme/js-style {:font-size 11 :line-height 16 :margin-top 8 :color (theme/c :muted)})}
       "Vous pouvez décrocher, Robine Wake garde le rythme."]]]))

(defn global-alarm-controls [session desktop?]
  [theme/glass-panel
   {:effect "regular" :tint "rgba(83,43,58,0.68)"
    :fallback-background "rgba(49,33,49,0.97)"
    :style {:position "absolute" :left (if desktop? 280 14)
            :right (if desktop? 24 14) :bottom (if desktop? 24 102)
            :padding 12 :border-radius 22 :flex-direction "row" :flex-wrap "wrap"
            :align-items "center" :gap 12
            :border-width 1 :border-color "rgba(255,140,163,0.35)"
            :shadow-color "#000" :shadow-opacity 0.35 :shadow-radius 18}}
   [:> View {:style (theme/js-style {:width 42 :height 42 :border-radius 21 :align-items "center"
                                     :justify-content "center" :background-color "rgba(255,140,163,0.14)"})}
    [theme/icon "pulse" 22 :rose]]
   [:> View {:style (theme/js-style {:flex 1})}
    [:> Text {:style (theme/js-style {:font-size 14 :font-weight "800" :color (theme/c :text)})}
     "Alarme en cours"]
    [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})}
     (if (= "strong" (:audio_phase session)) "Son de renfort" "Réveil progressif")]]
   (when (:test_mode session)
     [theme/button {:title "Arrêt direct" :compact true :on-press actions/dismiss!}])
   (if (not= false (:smartphone_dismiss_allowed session))
     [theme/button {:title (if (:test_mode session) "Tester l’arrêt" "Je suis levé")
                    :icon-name "sunny" :variant :primary :compact true
                    :on-press #(store/set-state! :challenge {:session-id (:id session)})}]
     [:> Text {:style (theme/js-style {:font-size 11 :font-weight "700"
                                       :color (theme/c :muted)})}
      "Arrêt sur le réveil"])])

(defn error-dialog [message]
  [:> Modal {:visible true :transparent true :animationType "fade"}
   [:> View {:style (theme/js-style {:flex 1 :justify-content "center" :padding 24
                                     :background-color "rgba(0,0,0,0.62)"})}
    [theme/card {:highlighted true}
     [:> View {:style (theme/js-style {:gap 16})}
      [:> Text {:style (theme/js-style {:font-size 20 :font-weight "800" :color (theme/c :text)})}
       "Connexion au réveil"]
      [:> Text {:style (theme/js-style {:font-size 14 :line-height 20 :color (theme/c :muted)})} message]
      [:> View {:style (theme/js-style {:flex-direction "row" :justify-content "flex-end" :gap 10})}
       [theme/button {:title "Fermer" :on-press store/clear-error!}]
       [theme/button {:title "Réessayer" :variant :primary
                      :on-press #(do (store/clear-error!) (transport/reconnect!))}]]]]]])

(defn current-screen [tab desktop?]
  (case tab
    :evening [screens/evening-screen desktop?]
    :alarms [screens/alarms-screen desktop?]
    :system [screens/system-screen desktop?]
    [screens/morning-screen desktop?]))

(defn root []
  (let [state @store/app-state
        desktop? (theme/desktop-width? @theme/viewport-width)]
    [:> SafeAreaProvider
     [:> View {:style (theme/js-style {:flex 1 :background-color (theme/c :night950)})}
      [theme/night-background]
      [:> StatusBar {:style "light"}]
      [:> View {:style (theme/js-style {:flex 1 :flex-direction (if desktop? "row" "column")})}
       (when desktop? [desktop-sidebar])
       [:> SafeAreaView {:edges (clj->js ["top"]) :style (theme/js-style {:flex 1})}
        [current-screen (:tab state) desktop?]]]
      (when-not desktop? [tab-bar])
      (when-let [session (:active-session state)] [global-alarm-controls session desktop?])
      (when-let [draft (:editor state)] [alarm-editor draft])
      (when (:challenge state) [wake-challenge])
      (when-let [error (:error state)] [error-dialog error])]]))

(defn start []
  (expo/render-root (r/as-element [root])))

(defn ^:export init []
  (install-browser-routing!)
  (transport/start!)
  (start))

(defn ^:dev/after-load reload []
  (apply-browser-route!)
  (start))
