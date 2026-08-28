(ns robine-wake.editor
  (:require [reagent.core :as r]
            [robine-wake.actions :as actions]
            [robine-wake.models :as models]
            [robine-wake.store :as store]
            [robine-wake.theme :as theme]
            ["react-native" :as rn]
            ["@react-native-community/datetimepicker" :default DateTimePicker]
            ["@react-native-community/slider" :default Slider]
            ["@react-native-picker/picker" :refer [Picker]]))

(def View (.-View rn))
(def Text (.-Text rn))
(def ScrollView (.-ScrollView rn))
(def Pressable (.-Pressable rn))
(def TextInput (.-TextInput rn))
(def Modal (.-Modal rn))
(def Alert (.-Alert rn))
(def Platform (.-Platform rn))
(def PickerItem (.-Item Picker))
(def web? (= "web" (.-OS Platform)))

(defn heading [number title subtitle]
  [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 12})}
   [:> View {:style (theme/js-style {:width 28 :height 28 :border-radius 14 :align-items "center"
                                     :justify-content "center" :background-color (theme/c :moon)})}
    [:> Text {:style (theme/js-style {:font-size 12 :font-weight "900" :color (theme/c :night950)})} number]]
   [:> View {:style (theme/js-style {:flex 1})}
    [:> Text {:style (theme/js-style {:font-size 17 :font-weight "700" :color (theme/c :text)})} title]
    [:> Text {:style (theme/js-style {:font-size 12 :margin-top 2 :color (theme/c :muted)})} subtitle]]])

(defn value-slider [draft key title minimum maximum suffix color]
  (let [value (get @draft key)]
    [:> View {:style (theme/js-style {:gap 9})}
     [:> View {:style (theme/js-style {:flex-direction "row"})}
      [:> Text {:style (theme/js-style {:flex 1 :font-size 14 :color (theme/c :text)})} title]
      [:> Text {:style (theme/js-style {:font-size 14 :font-weight "800" :color (theme/c color)})}
       (str value suffix)]]
     [:> Slider {:minimumValue minimum :maximumValue maximum :step 1 :value value
                 :minimumTrackTintColor (theme/c color)
                 :maximumTrackTintColor "rgba(255,255,255,0.14)"
                 :thumbTintColor (theme/c color)
                 :onValueChange #(swap! draft assoc key (js/Math.round %))}]]))

(defn sound-picker [draft key label detail icon-name color sounds]
  [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 13})}
   [:> View {:style (theme/js-style {:width 42 :height 42 :border-radius 13 :align-items "center"
                                     :justify-content "center" :background-color "rgba(245,207,135,0.12)"})}
    [theme/icon icon-name 21 color]]
   [:> View {:style (theme/js-style {:flex 1})}
    [:> Text {:style (theme/js-style {:font-size 14 :font-weight "700" :color (theme/c :text)})} label]
    [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})} detail]]
   [:> Picker {:selectedValue (get @draft key) :onValueChange #(swap! draft assoc key %)
               :dropdownIconColor (theme/c :moon)
               :style (theme/picker-style {:width 180})}
    (for [sound sounds]
      ^{:key (:id sound)} [:> PickerItem {:label (:title sound) :value (:id sound)}])]])

(defn time-date [draft]
  (let [date (js/Date.)]
    (.setHours date (:hour @draft) (:minute @draft) 0 0)
    date))

(defn time-card [draft]
  [theme/card {:highlighted true}
   [:> View {:style (theme/js-style {:align-items "center" :gap 12})}
    [theme/eyebrow "Quand commence le matin ?" :moon]
    (if web?
      [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 8})}
       [:> Picker {:selectedValue (:hour @draft)
                   :onValueChange #(swap! draft assoc :hour %)
                   :style (theme/picker-style {:width 104 :font-size 18 :font-weight "800"})}
        (for [hour (range 24)]
          ^{:key hour} [:> PickerItem {:label (.padStart (str hour) 2 "0") :value hour}])]
       [:> Text {:style (theme/js-style {:font-size 28 :font-weight "700" :color (theme/c :moon)})} ":"]
       [:> Picker {:selectedValue (:minute @draft)
                   :onValueChange #(swap! draft assoc :minute %)
                   :style (theme/picker-style {:width 104 :font-size 18 :font-weight "800"})}
        (for [minute (range 60)]
          ^{:key minute} [:> PickerItem {:label (.padStart (str minute) 2 "0") :value minute}])]]
      [:> DateTimePicker {:value (time-date draft) :mode "time" :display "spinner"
                          :themeVariant "dark" :minuteInterval 1
                          :onChange (fn [_ date]
                                      (when date
                                        (swap! draft assoc :hour (.getHours date) :minute (.getMinutes date))))
                          :style (theme/js-style {:height 126 :width 260})}])
    [:> TextInput {:value (:label @draft) :onChangeText #(swap! draft assoc :label %)
                   :placeholder "Nom du réveil" :placeholderTextColor (theme/c :muted)
                   :textAlign "center"
                   :style (theme/input-style {:align-self "stretch" :font-size 17 :font-weight "700"})}]
    [:> View {:style (theme/js-style {:align-self "stretch" :flex-direction "row" :align-items "center"})}
     [:> Text {:style (theme/js-style {:flex 1 :font-size 14 :font-weight "700" :color (theme/c :text)})}
      "Alarme active"]
     [theme/toggle {:value (:enabled @draft)
                    :accessibility-label "Alarme active"
                    :on-value-change #(swap! draft assoc :enabled %)}]]]])

(defn schedule-card [draft]
  [theme/card {}
   [:> View {:style (theme/js-style {:gap 16})}
    [heading "1" "Votre rythme" "Les jours où cette alarme revient"]
    [:> View {:style (theme/js-style {:flex-direction "row" :gap 7})}
     (for [{:keys [id short name]} models/weekdays]
       ^{:key id}
       [:> Pressable {:accessibilityLabel name
                      :onPress #(swap! draft update :days (fn [days]
                                                           (if (contains? days id) (disj days id) (conj days id))))
                      :style (theme/js-style {:flex 1 :height 38 :border-radius 19 :align-items "center"
                                              :justify-content "center"
                                              :background-color (if (contains? (:days @draft) id)
                                                                  (theme/c :moon) "rgba(255,255,255,0.06)" )})}
        [:> Text {:style (theme/js-style {:font-size 12 :font-weight "800"
                                          :color (if (contains? (:days @draft) id)
                                                   (theme/c :night950) (theme/c :muted))})} short]])]
    [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})}
     (str "🌍  " (:timezone @draft))]]])

(defn sound-card [draft sounds]
  [theme/card {}
   [:> View {:style (theme/js-style {:gap 16})}
    [heading "2" "Voyage sonore" "Doux d’abord, plus présent ensuite"]
    [sound-picker draft :sound-id "Première lumière" "Commence en douceur" "sunny" :moon sounds]
    [theme/divider]
    [sound-picker draft :strong-sound-id "Renfort" "Prend le relais si nécessaire" "pulse" :rose sounds]
    [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})}
     "◉  La sortie locale du réveil reste prioritaire pendant une alarme."]]])

(defn light-card [draft targets hue]
  [theme/card {}
   [:> View {:style (theme/js-style {:gap 16})}
    [heading "3" "Lever de lumière" "Une ambiance Philips Hue progressive"]
    (if (and (:configured hue) (seq targets))
      [:<>
       [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center"})}
        [:> Text {:style (theme/js-style {:flex 1 :font-size 14 :font-weight "700" :color (theme/c :text)})}
         "Allumer progressivement"]
        [theme/toggle {:value (:light-enabled @draft)
                       :accessibility-label "Allumer progressivement"
                       :on-value-change (fn [enabled]
                                          (swap! draft assoc :light-enabled enabled)
                                          (when (and enabled (nil? (:light-target-id @draft)))
                                            (swap! draft assoc :light-target-id (:id (first targets))
                                                   :light-target-name (:name (first targets)))))}]]
       (when (:light-enabled @draft)
         [:<>
          [:> Picker {:selectedValue (:light-target-id @draft)
                      :onValueChange (fn [id]
                                       (let [target (first (filter #(= id (:id %)) targets))]
                                         (swap! draft assoc :light-target-id id :light-target-name (:name target))))
                      :dropdownIconColor (theme/c :moon)
                      :style (theme/picker-style)}
           (for [target targets]
             ^{:key (:id target)} [:> PickerItem {:label (:name target) :value (:id target)}])]
          [value-slider draft :light-start-brightness "Première lueur" 1
           (:light-end-brightness @draft) "%" :moon]
          [value-slider draft :light-end-brightness "Lumière finale"
           (:light-start-brightness @draft) 100 "%" :mint]
          [value-slider draft :light-ramp-minutes "Durée lumière" 1 60 " min" :lavender]
          [:> Picker {:selectedValue (:light-end-behavior @draft)
                      :onValueChange #(swap! draft assoc :light-end-behavior %)
                      :dropdownIconColor (theme/c :moon)
                      :style (theme/picker-style)}
           [:> PickerItem {:label "Après l’arrêt · Restaurer" :value "restore"}]
           [:> PickerItem {:label "Après l’arrêt · Éteindre" :value "off"}]
           [:> PickerItem {:label "Après l’arrêt · Laisser" :value "leave"}]]])]
      [:> Text {:style (theme/js-style {:font-size 14 :color (theme/c :muted)})}
       "💡  Connectez d’abord un pont depuis l’onglet Réveil."])]] )

(defn ramp-card [draft]
  [theme/card {}
   [:> View {:style (theme/js-style {:gap 18})}
    [heading "4" "Montée progressive" "Le plafond est atteint à l’heure du réveil"]
    [value-slider draft :start-volume "Départ" 0 (:ceiling-volume @draft) "%" :mint]
    [value-slider draft :ceiling-volume "Plafond" (:start-volume @draft) 100 "%" :rose]
    [value-slider draft :prewake-minutes "Commencer avant l’heure" 1 60 " min avant" :lavender]
    [:> Text {:style (theme/js-style {:font-size 12 :line-height 17 :color (theme/c :muted)})}
     "Le volume reste au plafond pendant 5 minutes à l’heure choisie, puis le son de renfort prend le relais."]
    [:> View {:style (theme/js-style {:height 24 :flex-direction "row" :align-items "flex-end" :gap 4})}
     (for [index (range 12)]
       ^{:key index}
       [:> View {:style (theme/js-style {:flex 1 :height (+ 5 (* index 1.5)) :border-radius 999
                                         :background-color (if (< index (* 12 (/ (:ceiling-volume @draft) 100)))
                                                             (theme/c :lavender) "rgba(255,255,255,0.05)")
                                         :opacity (+ 0.35 (* index 0.045))})}])]]])

(defn snooze-card [draft]
  [theme/card {}
   [:> View {:style (theme/js-style {:gap 17})}
    [heading "5" "Répétition" "Une pause avant de relancer le réveil"]
    [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center"})}
     [:> Text {:style (theme/js-style {:flex 1 :font-size 14 :font-weight "700" :color (theme/c :text)})}
      "Autoriser la répétition"]
     [theme/toggle {:value (:snooze-enabled @draft)
                    :accessibility-label "Autoriser la répétition"
                    :on-value-change #(swap! draft assoc :snooze-enabled %)}]]
    (when (:snooze-enabled @draft)
      [:<>
       [value-slider draft :snooze-minutes "Pause" 1 30 " min" :moon]
       [value-slider draft :snooze-maximum "Maximum" 1 10 " fois" :lavender]])]])

(defn test-card [draft]
  [theme/card {}
   [:> View {:style (theme/js-style {:gap 14})}
    [:> View {:style (theme/js-style {:flex-direction "row" :align-items "center" :gap 13})}
     [theme/icon "play" 22 :moon]
     [:> View {:style (theme/js-style {:flex 1})}
      [:> Text {:style (theme/js-style {:font-size 17 :font-weight "700" :color (theme/c :text)})}
       "Lancer ce réveil"]
      [:> Text {:style (theme/js-style {:font-size 12 :color (theme/c :muted)})}
       "Reproduit exactement la séquence du matin"]]]
    [:> View {:style (theme/js-style {:flex-direction "row" :gap 10})}
     [theme/button {:title "Réveil complet" :grow true :on-press #(actions/trigger-alarm! (:id @draft))}]
     [theme/button {:title "Tester fort" :variant :primary :grow true
                    :on-press #(actions/trigger-strong! (:id @draft))}]]]])

(defn confirm-delete! [draft]
  (.alert Alert "Supprimer cette alarme ?" nil
          (clj->js [{:text "Annuler" :style "cancel"}
                    {:text "Supprimer" :style "destructive"
                     :onPress (fn []
                                (actions/close-editor!)
                                (actions/delete-alarm! draft))}])))

(defn alarm-editor [initial-draft]
  (r/with-let [draft (r/atom initial-draft)]
    (let [state @store/app-state
          desktop? (theme/desktop-width? @theme/viewport-width)]
      [:> Modal {:visible true :animationType "slide" :presentationStyle "pageSheet"
                 :onRequestClose actions/close-editor!}
       [:> View {:style (theme/js-style {:flex 1 :background-color (theme/c :night950)})}
        [theme/night-background]
        [:> View {:style (theme/js-style {:width "100%" :max-width (if desktop? 960 nil) :align-self "center"
                                          :padding-top 18 :padding-horizontal 18 :padding-bottom 12
                                          :flex-direction "row" :align-items "center"})}
         [theme/button {:title "Annuler" :compact true :on-press actions/close-editor!}]
         [:> Text {:style (theme/js-style {:flex 1 :text-align "center" :font-size 17 :font-weight "700"
                                           :color (theme/c :text)})}
          (if (:id @draft) "Modifier l’alarme" "Nouvelle alarme")]
         [:> View {:style (theme/js-style {:width 76})}]]
        [:> ScrollView {:contentContainerStyle (theme/js-style {:width "100%" :max-width (if desktop? 960 nil)
                                                                 :align-self "center" :padding 18
                                                                 :padding-bottom 48 :gap 18})
                        :showsVerticalScrollIndicator false}
         [time-card draft]
         [schedule-card draft]
         [sound-card draft (:sounds state)]
         [light-card draft (:hue-targets state) (:hue state)]
         [ramp-card draft]
         [snooze-card draft]
         (when (:id @draft) [test-card draft])
         [theme/button {:title (if (:id @draft) "Enregistrer les changements" "Créer l’alarme")
                        :variant :primary :grow true
                        :disabled (or (not (models/draft-valid? @draft)) (:busy? state))
                        :on-press #(actions/save-alarm! @draft)}]
         (when (:id @draft)
           [theme/button {:title "Supprimer l’alarme" :variant :danger
                          :on-press #(confirm-delete! @draft)}])]]])))
