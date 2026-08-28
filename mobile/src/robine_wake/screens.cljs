(ns robine-wake.screens
  (:require [clojure.string :as str]
            [reagent.core :as r]
            [robine-wake.actions :as actions]
            [robine-wake.models :as models]
            [robine-wake.store :as store]
            [robine-wake.theme :as theme]
            [robine-wake.transport :as transport]
            ["react-native" :as rn]
            ["@react-native-async-storage/async-storage" :default AsyncStorage]
            ["@react-native-community/slider" :default Slider]
            ["@react-native-picker/picker" :refer [Picker]]))

(def View (.-View rn))
(def Text (.-Text rn))
(def ScrollView (.-ScrollView rn))
(def Pressable (.-Pressable rn))
(def Switch (.-Switch rn))
(def TextInput (.-TextInput rn))
(def Alert (.-Alert rn))
(def Settings (.-Settings rn))

(def evening-volume-storage-key "robineWake.eveningVolumePercent.v4")
(defonce evening-volume (r/atom 60))

(defn valid-volume [value]
  (let [number (cond
                 (number? value) value
                 (string? value) (js/Number value)
                 :else js/NaN)]
    (when (and (js/Number.isFinite number) (<= 0 number 100))
      (js/Math.round number))))

(defn set-evening-volume! [value]
  (when-let [volume (valid-volume value)]
    (reset! evening-volume volume)
    (.setItem AsyncStorage evening-volume-storage-key (str volume))))

(defonce evening-volume-loader
  (-> (.getItem AsyncStorage evening-volume-storage-key)
      (.then
       (fn [stored]
         (when-let [volume (or (valid-volume stored)
                               (valid-volume (when Settings
                                               (.get Settings evening-volume-storage-key))))]
           (reset! evening-volume volume)
           (.setItem AsyncStorage evening-volume-storage-key (str volume)))))
      (.catch (fn [_] nil))))

(defn page-content-style
  ([desktop?] (page-content-style desktop? nil))
  ([desktop? overrides]
   (theme/js-style {:width "100%" :max-width (if desktop? 1180 nil) :align-self "center"
                    :padding-horizontal (if desktop? 32 18)
                    :padding-top (if desktop? 8 0)
                    :padding-bottom (if desktop? 40 120) :gap (if desktop? 22 18)}
                   overrides)))

(defn dashboard-card-style [desktop?]
  (when desktop?
    {:flex-basis "47%" :flex-grow 1 :min-width 320}))

(defn connection-label [state]
  (case (:connection state)
    :scanning "Recherche…"
    :connecting "Connexion…"
    :connected (if (= :http (:transport state)) "Wi-Fi" "À proximité")
    :disconnected "Déconnecté"
    "Bluetooth indisponible"))

(defn brand-header []
  (let [state @store/app-state]
    [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 12})}
     [theme/crescent 28]
     [:> View {:style (theme/js-style {:flex 1})}
      [:> Text {:style (theme/js-style {:font-size 12 :font-weight "800" :letter-spacing 1.8
                                        :color (theme/c :text)})} "ROBINE WAKE"]
      [:> Text {:style (theme/js-style {:font-size 12 :margin-top 2 :color (theme/c :muted)})}
       "Un réveil qui commence doucement"]]
     [theme/status-pill {:title (connection-label state)
                         :connected (or (:http-endpoint state) (= :connected (:connection state)))
                         :busy (:busy? state)}]]))

(defn dashboard-greeting []
  (let [state @store/app-state]
    [:> View {:style (theme/js-style {:flex-direction "row" :align-items "flex-end" :gap 18
                                      :padding-vertical 8})}
     [:> View {:style (theme/js-style {:flex 1 :gap 5})}
      [theme/eyebrow "Votre cocon" :moon]
      [:> Text {:style (theme/js-style {:font-size 32 :font-weight "750" :letter-spacing -0.8
                                        :color (theme/c :text)})}
       "Bonsoir"]
      [:> Text {:style (theme/js-style {:font-size 14 :color (theme/c :muted)})}
       "Le réveil veille sur votre prochain matin."]]
     [theme/status-pill {:title (connection-label state)
                         :connected (or (:http-endpoint state) (= :connected (:connection state)))
                         :busy (:busy? state)}]]))

(defn clock-hero []
  (r/with-let [now (r/atom (js/Date.))
               timer (js/setInterval #(reset! now (js/Date.)) 30000)]
    (let [date @now
          time (.format (js/Intl.DateTimeFormat. "fr-FR" #js {:hour "2-digit" :minute "2-digit"}) date)
          day (.format (js/Intl.DateTimeFormat. "fr-FR" #js {:weekday "long" :day "numeric" :month "long"}) date)]
      [:> View {:style (theme/js-style {:align-items "center" :padding-vertical 20 :gap 8})}
       [theme/eyebrow "Votre matin" :moon]
       [:> Text {:style (theme/js-style {:font-size 68 :line-height 76 :font-weight "500"
                                         :font-variant ["tabular-nums"] :color (theme/c :text)})} time]
       [:> Text {:style (theme/js-style {:font-size 15 :color (theme/c :muted)})} day]
       [:> Text {:style (theme/js-style {:font-size 12 :margin-top 8 :color (theme/c :moon-soft)})}
        "Tout est calme. Robine Wake garde le rythme."]])
    (finally (js/clearInterval timer))))

(defn compact-alarm-row [alarm]
  [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 12
                                    :opacity (if (:enabled alarm) 1 0.5)})}
   [:> Text {:style (theme/js-style {:font-size 23 :font-weight "700" :font-variant ["tabular-nums"]
                                     :color (theme/c :text)})}
    (subs (:local_time alarm) 0 5)]
   [:> View {:style (theme/js-style {:flex 1})}
    [:> Text {:style (theme/js-style {:font-size 14 :font-weight "700" :color (theme/c :text)})}
     (:label alarm)]
    [:> Text {:style (theme/js-style {:font-size 12 :margin-top 2 :color (theme/c :muted)})}
     (models/schedule-label alarm)]]
   [theme/icon "chevron-forward" 16 :muted]])

(defn active-session-card [session]
  [theme/card {:highlighted true}
   [:> View {:style (theme/js-style {:gap 15})}
    [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center"})}
     [theme/eyebrow "Réveil en cours" :rose]
     [:> View {:style (theme/js-style {:flex 1})}]
     [theme/icon "pulse" 22 :rose]]
    [:> Text {:style (theme/js-style {:font-size 20 :font-weight "700" :color (theme/c :text)})}
     (if (= "strong" (:audio_phase session)) "Le son de renfort joue" "La lumière sonore monte doucement")]
    [:> View {:style (theme/js-style {:flex-direction "row" :gap 12})}
     [theme/button {:title "Répéter" :on-press actions/snooze!}]
     (if (not= false (:smartphone_dismiss_allowed session))
       [theme/button {:title "Je suis levé" :variant :primary
                      :on-press #(store/set-state! :challenge {:session-id (:id session)})}]
       [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 7})}
        [theme/icon "phone-portrait-outline" 17 :muted]
        [:> Text {:style (theme/js-style {:font-size 11 :font-weight "700"
                                          :color (theme/c :muted)})}
         "Arrêt sur le réveil"]])]]]])

(defn clock-warning []
  [theme/card {}
   [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 14})}
    [theme/icon "time" 28 :moon]
    [:> View {:style (theme/js-style {:flex 1})}
     [:> Text {:style (theme/js-style {:font-size 17 :font-weight "700" :color (theme/c :text)})}
      "Heure à confirmer"]
     [:> Text {:style (theme/js-style {:font-size 12 :margin-top 3 :color (theme/c :muted)})}
      "Vérifiez l’heure avant d’activer un réveil."]]
    [theme/button {:title "Confirmer" :compact true :on-press actions/confirm-clock!}]]])

(defn next-wake-card [alarm]
  (if alarm
    [:> Pressable {:onPress #(actions/edit-alarm! alarm)}
     [theme/card {:highlighted true}
      [:> View {:style (theme/js-style {:gap 15})}
       [:> View {:style (theme/js-style {:flex-direction "row"})}
        [theme/eyebrow "Prochain réveil" :moon]
        [:> View {:style (theme/js-style {:flex 1})}]
        [theme/icon "chevron-forward" 17 :muted]]
       [:> View {:style (theme/js-style {:flex-direction "row" :align-items "baseline"})}
        [:> Text {:style (theme/js-style {:flex 1 :font-size 46 :font-weight "700"
                                          :font-variant ["tabular-nums"] :color (theme/c :text)})}
         (subs (:local_time alarm) 0 5)]
        [:> Text {:style (theme/js-style {:font-size 17 :font-weight "700" :color (theme/c :moon-soft)})}
         (:label alarm)]]
       [:> View {:style (theme/js-style {:flex-direction "row" :gap 17})}
        [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})}
         (str "◫  " (models/schedule-label alarm))]
        [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})}
         (str "〽  " (quot (or (:prewake_seconds alarm) (get-in alarm [:volume_profile :ramp_seconds])) 60) " min avant")]]]]]
    [:> Pressable {:onPress actions/create-alarm!}
     [theme/card {:highlighted true}
      [:> View {:style (theme/js-style {:align-items "center" :gap 14})}
       [theme/icon "alarm" 34 :moon]
       [:> Text {:style (theme/js-style {:font-size 17 :font-weight "700" :color (theme/c :text)})}
        "Préparer votre premier matin"]
       [:> Text {:style (theme/js-style {:font-size 14 :text-align "center" :color (theme/c :muted)})}
        "Choisissez l’heure, le voyage sonore et la montée progressive."]
       [theme/button {:title "Créer une alarme" :variant :primary :on-press actions/create-alarm!}]]]]))

(defn alarm-list-card [alarms]
  [theme/card {}
   [:> View {:style (theme/js-style {:gap 14})}
    [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center"})}
     [theme/eyebrow "Vos alarmes"]
     [:> View {:style (theme/js-style {:flex 1})}]
     [theme/icon-button {:icon-name "add" :label "Ajouter une alarme"
                         :on-press actions/create-alarm!}]]
    (if (seq alarms)
      (for [[index alarm] (map-indexed vector (take 3 alarms))]
        ^{:key (:id alarm)}
        [:<>
         (when (pos? index) [theme/divider])
         [:> Pressable {:onPress #(actions/edit-alarm! alarm)} [compact-alarm-row alarm]]])
      [:> Text {:style (theme/js-style {:font-size 14 :color (theme/c :muted)})}
       "Aucune alarme enregistrée."])]])

(defn morning-screen [desktop?]
  (let [state @store/app-state
        next-alarm (first (sort-by #(or (first (:next_occurrences %)) (:local_time %))
                                   (filter :enabled (:alarms state))))]
    [:> ScrollView {:contentContainerStyle (page-content-style desktop?)
                    :showsVerticalScrollIndicator false}
     (if desktop? [dashboard-greeting] [brand-header])
     (if desktop?
       [:> View {:style (theme/js-style {:flex-direction "row" :align-items "flex-start" :gap 22})}
        [:> View {:style (theme/js-style {:flex 0.82 :gap 22})}
         [theme/morning-sky true [clock-hero]]
         (when-let [session (:active-session state)] [active-session-card session])
         (when (= false (get-in state [:device :clock_trusted])) [clock-warning])]
        [:> View {:style (theme/js-style {:flex 1.18 :gap 22})}
         [next-wake-card next-alarm]
         [alarm-list-card (:alarms state)]]]
       [:<>
        [theme/morning-sky false [clock-hero]]
        (when-let [session (:active-session state)] [active-session-card session])
        (when (= false (get-in state [:device :clock_trusted])) [clock-warning])
        [next-wake-card next-alarm]
        [alarm-list-card (:alarms state)]])]))

(defn confirm-full-alarm! [alarm]
  (.alert Alert
          (str "Lancer « " (:label alarm) " » comme demain matin ?")
          (str "La séquence réelle démarre maintenant : montée pendant "
               (quot (or (:prewake_seconds alarm) (get-in alarm [:volume_profile :ramp_seconds])) 60)
               " minutes, plafond pendant 5 minutes, puis son de renfort.")
          (clj->js [{:text "Annuler" :style "cancel"}
                    {:text "Lancer le réveil complet" :onPress #(actions/trigger-alarm! (:id alarm))}])))

(defn confirm-strong! [alarm]
  (.alert Alert
          (str "Tester directement la phase forte de « " (:label alarm) " » ?")
          "Le son de renfort démarrera au volume maximal configuré et les couleurs alterneront toutes les 3 secondes."
          (clj->js [{:text "Annuler" :style "cancel"}
                    {:text "Lancer la phase forte" :onPress #(actions/trigger-strong! (:id alarm))}])))

(defn alarm-card [alarm]
  (let [state @store/app-state]
    [theme/card {}
     [:> View {:style (theme/js-style {:gap 14 :opacity (if (:enabled alarm) 1 0.55)})}
      [:> View {:style (theme/js-style {:flex-direction "row" :align-items "flex-start"})}
       [:> Pressable {:style (theme/js-style {:flex 1}) :onPress #(actions/edit-alarm! alarm)}
        [:> Text {:style (theme/js-style {:font-size 38 :font-weight "700" :font-variant ["tabular-nums"]
                                          :color (theme/c :text)})} (subs (:local_time alarm) 0 5)]
        [:> Text {:style (theme/js-style {:font-size 17 :font-weight "700" :margin-top 4 :color (theme/c :text)})}
         (:label alarm)]
        [:> Text {:style (theme/js-style {:font-size 14 :margin-top 5 :color (theme/c :muted)})}
         (models/schedule-label alarm)]]
       [:> Switch {:value (:enabled alarm)
                   :disabled (:busy? state)
                   :trackColor #js {:false "#34374A" :true "#7C7AC4"}
                   :thumbColor (theme/c :moon)
                   :onValueChange #(actions/set-alarm-enabled! alarm %)}]]
      [theme/divider]
      [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 9})}
       [:> Text {:style (theme/js-style {:flex 1 :font-size 12 :font-weight "700" :color (theme/c :lavender)})}
        "🔈 Doux  →  🔊 Renfort"]
       [theme/button {:title "Réveil complet" :icon-name "play" :variant :primary :compact true
                      :disabled (:busy? state) :on-press #(confirm-full-alarm! alarm)}]
       [theme/button {:title "Fort" :icon-name "flash" :variant :danger :compact true
                      :disabled (:busy? state) :on-press #(confirm-strong! alarm)}]]]]))

(defn alarms-screen [desktop?]
  (let [state @store/app-state]
    [:> View {:style (theme/js-style {:flex 1})}
     [theme/screen-title "Alarmes" {:title "Ajouter" :icon-name "add" :on-press actions/create-alarm!
                                    :desktop? desktop? :disabled (:busy? state)}]
     [:> ScrollView {:contentContainerStyle (page-content-style desktop?)
                     :showsVerticalScrollIndicator false}
      (if (seq (:alarms state))
        [:> View {:style (theme/js-style {:flex-direction (if desktop? "row" "column")
                                          :flex-wrap (if desktop? "wrap" "nowrap") :gap 16})}
         (for [alarm (:alarms state)]
           ^{:key (:id alarm)}
           [:> View {:style (theme/js-style (when desktop? {:flex-basis "47%" :flex-grow 1}))}
            [alarm-card alarm]])]
        [theme/card {:highlighted true}
         [:> View {:style (theme/js-style {:align-items "center" :gap 16 :padding-vertical 20})}
          [theme/crescent 50]
          [:> Text {:style (theme/js-style {:font-size 22 :font-weight "700" :color (theme/c :text)})}
           "Vos matins commencent ici"]
          [:> Text {:style (theme/js-style {:font-size 14 :text-align "center" :color (theme/c :muted)})}
           "Créez un réveil à deux étapes, doux puis plus présent si nécessaire."]
          [theme/button {:title "Créer une alarme" :variant :primary :on-press actions/create-alarm!}]]])]]))

(def PickerItem (.-Item Picker))

(defn phase-legend [color title detail]
  [:> View {:style (theme/js-style {:flex 1 :flex-direction "row" :align-items "center" :gap 9
                                    :padding 11 :border-radius 13
                                    :background-color "rgba(255,255,255,0.05)"})}
   [:> View {:style (theme/js-style {:width 12 :height 12 :border-radius 6
                                     :background-color (theme/c color)})}]
   [:> View {:style (theme/js-style {:flex 1})}
    [:> Text {:style (theme/js-style {:font-size 12 :font-weight "700" :color (theme/c :text)})} title]
    [:> Text {:style (theme/js-style {:font-size 10 :margin-top 1 :color (theme/c :muted)})} detail]]])

(defn breathing-guide [breathing]
  (r/with-let [tick (r/atom (js/Date.now))
               timer (js/setInterval #(reset! tick (js/Date.now)) 250)]
    (let [phase (or (:phase breathing) "inhale")
          duration (max 1 (or (:phase_duration_ms breathing) (if (= phase "inhale") 4000 6000)))
          started (some-> (:phase_started_at breathing) js/Date. .getTime)
          elapsed (if started (max 0 (- @tick started)) (or (:phase_elapsed_ms breathing) 0))
          progress (min 1 (/ elapsed duration))
          inhale? (= phase "inhale")
          color (if inhale? :breathing-inhale-amber :breathing-exhale-rose)
          size (+ 118 (* 54 (if inhale? progress (- 1 progress))))]
      [:> View {:style (theme/js-style {:align-items "center" :gap 14 :padding-vertical 8})}
       [:> View {:style (theme/js-style {:width 190 :height 190 :align-items "center" :justify-content "center"})}
        [:> View {:style (theme/js-style {:width size :height size :border-radius 999
                                          :background-color (theme/c color) :opacity 0.82
                                          :shadow-color (theme/c color) :shadow-opacity 0.5 :shadow-radius 28})}]
        [:> Text {:style (theme/js-style {:position "absolute" :font-size 20 :font-weight "800"
                                          :color (theme/c :text)})}
         (if inhale? "Inspirez" "Expirez")]]
       [:> Text {:style (theme/js-style {:font-size 13 :color (theme/c :muted)})}
        (str (or (:remaining_seconds breathing) "—") " s restantes")]])
    (finally (js/clearInterval timer))))

(defn volume-control [volume active? set-volume!]
  [:> View {:style (theme/js-style {:gap 8 :padding 12 :border-radius 13
                                    :background-color "rgba(255,255,255,0.05)"})}
   [:> View {:style (theme/js-style {:flex-direction "row"})}
    [:> Text {:style (theme/js-style {:flex 1 :font-size 14 :font-weight "700" :color (theme/c :text)})}
     (str (if (zero? volume) "🔇" "🔊") "  Volume")]
    [:> Text {:style (theme/js-style {:font-size 14 :font-weight "700" :color (theme/c :moon)})}
     (str volume " %")]]
   [:> Slider {:minimumValue 0 :maximumValue 100 :step 5 :value volume
               :minimumTrackTintColor (theme/c :moon)
               :maximumTrackTintColor "rgba(255,255,255,0.15)"
               :thumbTintColor (theme/c :moon)
               :onValueChange #(set-volume! (js/Math.round %))
               :onSlidingComplete #(when active? (actions/breathing-volume! (js/Math.round %)))}]])

(defn evening-screen [desktop?]
  (r/with-let [target-id (r/atom "")
               duration (r/atom 10)]
    (let [state @store/app-state
          targets (:hue-targets state)
          breathing (get-in state [:hue :breathing])
          active? (boolean (:active breathing))
          selected (if (some #(= @target-id (:id %)) targets)
                     @target-id
                     (or (:target_id breathing) (:id (first targets)) ""))]
      (when (and (str/blank? @target-id) (not (str/blank? selected))) (reset! target-id selected))
      (when-let [active-volume (get-in breathing [:audio :volume_percent])]
        (when (and active? (not= active-volume @evening-volume))
          (set-evening-volume! active-volume)))
      [:> View {:style (theme/js-style {:flex 1})}
       [theme/screen-title "Le soir" {:title "Actualiser" :icon-name "refresh" :desktop? desktop?
                                      :compact true :disabled (:busy? state)
                                      :on-press #(if (get-in state [:hue :configured])
                                                   (actions/refresh-hue!) (transport/refresh!))}]
       [:> ScrollView {:contentContainerStyle (page-content-style desktop?
                                                                  (when desktop?
                                                                    {:flex-direction "row"
                                                                     :flex-wrap "wrap"
                                                                     :align-items "flex-start"}))
                       :showsVerticalScrollIndicator false}
        [theme/card {:highlighted true :style (dashboard-card-style desktop?)}
         [:> View {:style (theme/js-style {:align-items "center" :gap 14})}
          [theme/crescent 44]
          [theme/eyebrow "Rituel du soir" :twilight-rose]
          [:> Text {:style (theme/js-style {:font-size 23 :font-weight "700" :color (theme/c :text)})}
           "Ralentir avant la nuit"]
          [:> Text {:style (theme/js-style {:font-size 14 :text-align "center" :color (theme/c :muted)})}
           "Une respiration guidée par la lumière, douce et autonome, pour laisser la journée retomber."]]]
        [theme/card {:highlighted active? :style (dashboard-card-style desktop?)}
         [:> View {:style (theme/js-style {:gap 15})}
          [:> View {:style (theme/js-style {:flex-direction "row"})}
           [theme/eyebrow "Respiration 4 / 6" :twilight-rose]
           [:> View {:style (theme/js-style {:flex 1})}]
           [theme/icon "bulb" 21 :breathing-inhale-amber]]
          (if active?
            [:<>
             [breathing-guide breathing]
             [:> Text {:style (theme/js-style {:font-size 12 :font-weight "700"
                                                :color (theme/c (if (get-in breathing [:audio :active]) :mint :rose))})}
              (if (get-in breathing [:audio :active])
                "🔊  Jardin sonore synchronisé avec la lumière"
                "🔇  La lumière continue sans ambiance sonore")]
             [volume-control @evening-volume true set-evening-volume!]
             [theme/button {:title "Terminer et restaurer la lumière" :icon-name "stop"
                            :variant :primary :disabled (:busy? state) :on-press actions/stop-breathing!}]]
            [:<>
             [:> Text {:style (theme/js-style {:font-size 14 :line-height 20 :color (theme/c :muted)})}
              "L’orage reste naturel et constant. La lumière glisse directement de l’ambre doré au rose crépusculaire, sans passer par le blanc ; seule son intensité évolue lentement."]
             [:> View {:style (theme/js-style {:flex-direction "row" :gap 14})}
              [phase-legend :breathing-inhale-amber "Inspiration" "4 s · ambre doré · 2 → 30 %"]
              [phase-legend :breathing-exhale-rose "Expiration" "6 s · rose crépusculaire · 30 → 2 %"]]
             [:> Picker {:selectedValue selected :onValueChange #(reset! target-id %)
                         :dropdownIconColor (theme/c :moon)
                         :style (theme/picker-style)}
              (for [target targets]
                ^{:key (:id target)} [:> PickerItem {:label (:name target) :value (:id target)}])]
             [:> Picker {:selectedValue @duration :onValueChange #(reset! duration %)
                         :dropdownIconColor (theme/c :moon)
                         :style (theme/picker-style)}
              (for [minutes [3 5 10 15 20 30]]
                ^{:key minutes} [:> PickerItem {:label (str minutes " minutes") :value minutes}])]
             [volume-control @evening-volume false set-evening-volume!]
             [theme/button {:title "Commencer la séance" :icon-name "play" :variant :primary
                            :disabled (or (:busy? state) (not (get-in state [:hue :configured])) (str/blank? selected))
                            :on-press #(actions/start-breathing! selected @duration @evening-volume)}]
             (cond
               (not (get-in state [:hue :configured]))
               [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :rose)})}
                "💡  Configurez d’abord Philips Hue dans l’onglet Réveil."]
               (not= "available" (get-in state [:hue :state]))
               [theme/button {:title "Réessayer la connexion Hue" :compact true
                              :disabled (:busy? state) :on-press actions/refresh-hue!}])])]]]])))

(defn status-label [value]
  (case value "available" "Disponible" "unavailable" "Indisponible"
        (if value (str/capitalize value) "—")))

(defn date-label [value]
  (if value
    (.format (js/Intl.DateTimeFormat. "fr-FR" #js {:dateStyle "short" :timeStyle "short"}) (js/Date. value))
    "—"))

(defn discover-hue! [discovery]
  (reset! discovery {:state :searching :bridges []})
  (-> (js/fetch "https://discovery.meethue.com/")
      (.then #(.json %))
      (.then (fn [values]
               (let [bridges (mapv (fn [^js bridge]
                                     {:id (.-id bridge) :host (.-internalipaddress bridge)
                                      :name (str "Pont Hue " (.-id bridge))})
                                   (array-seq values))]
                 (reset! discovery {:state (if (seq bridges) :found :unavailable) :bridges bridges}))))
      (.catch #(reset! discovery {:state :unavailable :bridges []}))))

(defn hue-card [bridge-host discovery desktop?]
  (let [state @store/app-state
        hue (:hue state)]
    [theme/card {:highlighted (= "available" (:state hue))
                 :style (dashboard-card-style desktop?)}
     [:> View {:style (theme/js-style {:gap 15})}
      [:> View {:style (theme/js-style {:flex-direction "row"})}
       [theme/eyebrow "Philips Hue" :moon]
       [:> View {:style (theme/js-style {:flex 1})}]
       [theme/icon "bulb" 22 :moon]]
      (if (:configured hue)
        [:<>
         [theme/metric-row {:icon-name "git-network" :title "Pont local"
                            :detail (or (:bridge_host hue) "Connecté")
                            :color (if (= "available" (:state hue)) :mint :rose)}]
         [theme/metric-row {:icon-name "albums" :title "Pièces et zones"
                            :detail (str (or (:target_count hue) 0) " disponibles")}]
         [:> View {:style (theme/js-style {:flex-direction "row" :gap 10})}
          [theme/button {:title "Actualiser" :on-press actions/refresh-hue!}]
          [theme/button {:title "Déconnecter" :variant :danger :on-press actions/disconnect-hue!}]]]
        [:<>
         [:> Text {:style (theme/js-style {:font-size 14 :line-height 20 :color (theme/c :muted)})}
          "Les ponts Hue présents sur le même réseau sont découverts automatiquement. Appuyez sur le bouton rond du pont juste avant de le connecter."]
         (case (:state @discovery)
           :searching [:> Text {:style (theme/js-style {:font-size 13 :color (theme/c :muted)})}
                       "◌  Recherche des ponts Hue…"]
           :found (for [bridge (:bridges @discovery)]
                    ^{:key (:id bridge)}
                    [:> Pressable {:onPress #(do (reset! bridge-host (:host bridge))
                                                 (actions/pair-hue! (:host bridge)))}
                     [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 12
                                                       :padding 12 :border-radius 13
                                                       :background-color "rgba(255,255,255,0.06)"})}
                      [theme/icon "shield-checkmark" 20 :moon]
                      [:> View {:style (theme/js-style {:flex 1})}
                       [:> Text {:style (theme/js-style {:font-size 14 :font-weight "700" :color (theme/c :text)})}
                        (:name bridge)]
                       [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})} (:host bridge)]]
                      [:> Text {:style (theme/js-style {:font-size 12 :font-weight "700" :color (theme/c :moon)})}
                       "Connecter  ›"]]])
           :unavailable [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :rose)})}
                         "⚠  Aucun pont résolu. Utilisez l’adresse manuelle."]
           nil)
         [theme/button {:title "Rechercher à nouveau" :compact true
                        :disabled (= :searching (:state @discovery))
                        :on-press #(discover-hue! discovery)}]
         [:> TextInput {:value @bridge-host :onChangeText #(reset! bridge-host %)
                        :placeholder "Adresse manuelle · ex. 192.168.1.42"
                        :placeholderTextColor (theme/c :muted)
                        :autoCapitalize "none" :autoCorrect false :keyboardType "url"
                        :style (theme/input-style)}]
         [theme/button {:title "Connecter cette adresse" :variant :primary
                        :disabled (or (str/blank? @bridge-host) (:busy? state))
                        :on-press #(actions/pair-hue! (str/trim @bridge-host))}]])
      (when (= "unavailable" (:state hue))
        [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :rose)})}
         "⚠  Le pont est enregistré mais momentanément inaccessible."])]]))

(defn remote-button-card [desktop?]
  (let [state @store/app-state
        remote (:remote-button state)
        pairing? (get-in remote [:pairing :active])]
    [theme/card {:highlighted pairing? :style (dashboard-card-style desktop?)}
     [:> View {:style (theme/js-style {:gap 15})}
      [:> View {:style (theme/js-style {:flex-direction "row"})}
       [theme/eyebrow "Bouton déporté" :mint]
       [:> View {:style (theme/js-style {:flex 1})}]
       [theme/icon "radio-button-on" 21 :mint]]
      [:> Text {:style (theme/js-style {:font-size 14 :line-height 20 :color (theme/c :muted)})}
       "Arrêt sécurisé en LoRa 868 MHz. Le Raspberry écoute directement le bouton, sans Internet ni routeur. Chaque appui est signé et protégé contre le rejeu."]
      (for [button (:buttons remote)]
        ^{:key (:id button)}
        [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 12})}
         [theme/icon "shield-checkmark" 21 :mint]
         [:> View {:style (theme/js-style {:flex 1})}
          [:> Text {:style (theme/js-style {:font-size 14 :font-weight "700" :color (theme/c :text)})} (:name button)]
          [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})}
           (if (:last_seen_at button) (date-label (:last_seen_at button)) "Jamais utilisé")]]
         [theme/button {:title "Oublier" :variant :danger :compact true
                        :disabled (:busy? state) :on-press #(actions/remove-button! (:id button))}]])
      (if pairing?
        [:> Text {:style (theme/js-style {:font-size 12 :font-weight "700" :color (theme/c :moon)})}
         "⌁  Association ouverte pendant 2 minutes. Maintenez maintenant le bouton physique enfoncé."]
        [theme/button {:title "Associer un bouton" :variant :primary
                       :disabled (:busy? state) :on-press actions/begin-button-pairing!}])]]))

(defn smartphone-dismiss-card [desktop?]
  (let [state @store/app-state
        setting (:smartphone-dismiss state)
        enabled? (not= false (:enabled setting))
        locked? (or (:locked setting) (some? (:active-session state)))]
    [theme/card {:highlighted (not enabled?) :style (dashboard-card-style desktop?)}
     [:> View {:style (theme/js-style {:gap 13})}
      [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center"})}
       [theme/eyebrow "Arrêt de l’alarme" :rose]
       [:> View {:style (theme/js-style {:flex 1})}]
       [:> Switch {:value enabled?
                   :disabled (or locked? (:busy? state))
                   :onValueChange actions/set-smartphone-dismiss!
                   :trackColor (clj->js {:false "rgba(255,140,163,0.25)"
                                         :true "rgba(120,217,188,0.55)"})
                   :thumbColor (if enabled? (theme/c :mint) (theme/c :muted))}]]
      [:> Text {:style (theme/js-style {:font-size 14 :line-height 20
                                        :color (theme/c :muted)})}
       (if enabled?
         "Le smartphone peut arrêter une alarme après le défi de réveil."
         "L’alarme doit être arrêtée depuis le réveil ou le bouton déporté.")]
      (when locked?
        [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 8})}
         [theme/icon "lock-closed" 16 :moon]
         [:> Text {:style (theme/js-style {:font-size 11 :font-weight "700"
                                           :color (theme/c :moon)})}
          "Réglage verrouillé jusqu’à la fin de l’alarme en cours."]])]]))

(defn system-screen [desktop?]
  (r/with-let [bridge-host (r/atom "")
               discovery (r/atom {:state :idle :bridges []})
               _ (when-not (get-in @store/app-state [:hue :configured]) (discover-hue! discovery))]
    (let [state @store/app-state]
      [:> View {:style (theme/js-style {:flex 1})}
       [theme/screen-title "Le réveil" {:title "Actualiser" :icon-name "refresh" :desktop? desktop?
                                       :disabled (:busy? state) :on-press transport/refresh!}]
       [:> ScrollView {:contentContainerStyle (page-content-style desktop?
                                                                  (when desktop?
                                                                    {:flex-direction "row"
                                                                     :flex-wrap "wrap"
                                                                     :align-items "flex-start"}))
                       :showsVerticalScrollIndicator false}
        [theme/card {:style (dashboard-card-style desktop?)}
         [:> View {:style (theme/js-style {:gap 14})}
          [theme/eyebrow "État du réveil" :mint]
          [theme/metric-row {:icon-name "radio" :title "Canal actif" :detail (connection-label state) :color :mint}]
          [theme/metric-row {:icon-name "code-working" :title "API locale"
                             :detail (or (some-> (:http-endpoint state) (str/replace #"^https?://" "") (str/split #":") first)
                                         "À découvrir")}]
          [theme/metric-row {:icon-name "wifi" :title "Réseau" :detail (status-label (get-in state [:device :network :state]))}]
          [theme/metric-row {:icon-name "volume-high" :title "Audio" :detail (status-label (get-in state [:device :audio :state])) :color :moon}]
          [theme/metric-row {:icon-name "cube" :title "Logiciel" :detail (or (get-in state [:device :firmware :version]) "—")}]]]
        [hue-card bridge-host discovery desktop?]
        [smartphone-dismiss-card desktop?]
        [remote-button-card desktop?]
        [theme/card {:style (dashboard-card-style desktop?)}
         [:> View {:style (theme/js-style {:gap 15})}
          [theme/eyebrow "Bibliothèque sonore" :moon]
          (for [sound (take 8 (:sounds state))]
            ^{:key (:id sound)}
            [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 12})}
             [theme/icon (if (= "strong" (:intensity sound)) "pulse" "musical-notes") 20
              (if (= "strong" (:intensity sound)) :rose :moon)]
             [:> View {:style (theme/js-style {:flex 1})}
              [:> Text {:style (theme/js-style {:font-size 14 :font-weight "600" :color (theme/c :text)})} (:title sound)]
              (when-let [artist (:artist sound)]
                [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})} artist])]
             [:> Text {:style (theme/js-style {:font-size 10 :font-weight "800" :color (theme/c :muted)})}
              (str/upper-case (or (:intensity sound) ""))]])]]
        (when (seq (:recent-sessions state))
          [theme/card {:style (dashboard-card-style desktop?)}
           [:> View {:style (theme/js-style {:gap 14})}
            [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center"})}
             [theme/eyebrow "Matins récents"]
             [:> View {:style (theme/js-style {:flex 1})}]
             [theme/button {:title "Effacer" :variant :danger :compact true
                            :on-press #(.alert Alert "Effacer tout l’historique ?" nil
                                               (clj->js [{:text "Annuler" :style "cancel"}
                                                         {:text "Effacer" :style "destructive"
                                                          :onPress actions/erase-history!}]))}]]
            (for [session (take 5 (:recent-sessions state))]
              ^{:key (:id session)}
              [theme/metric-row {:icon-name (if (= "dismissed" (:state session)) "checkmark-circle" "time")
                                 :title (str/capitalize (or (:state session) "Session"))
                                 :detail (date-label (:ended_at session))
                                 :color (if (= "dismissed" (:state session)) :mint :lavender)}])]])]])))
