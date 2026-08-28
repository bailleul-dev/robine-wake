(ns robine-wake.challenge
  (:require [clojure.string :as str]
            [reagent.core :as r]
            [robine-wake.actions :as actions]
            [robine-wake.models :as models]
            [robine-wake.store :as store]
            [robine-wake.theme :as theme]
            ["react-native" :as rn]
            ["expo-linear-gradient" :refer [LinearGradient]]
            ["expo-haptics" :as Haptics]))

(def View (.-View rn))
(def Text (.-Text rn))
(def Pressable (.-Pressable rn))
(def Modal (.-Modal rn))

(defn progress [step]
  [:> View {:style (theme/js-style {:flex-direction "row" :gap 8})}
   (for [index (range 3)]
     ^{:key index}
     [:> View {:style (theme/js-style {:flex 1 :height 7 :border-radius 99
                                       :background-color (cond (< index step) (theme/c :mint)
                                                               (= index step) (theme/c :moon)
                                                               :else "rgba(255,255,255,0.14)")})}])])

(defn wake-challenge []
  (r/with-let [step (r/atom 0)
               challenge (r/atom (models/make-challenge 0))
               feedback (r/atom nil)
               answering? (r/atom false)]
    (letfn [(complete! []
              (store/set-state! :challenge nil)
              (actions/dismiss!))
            (answer! [value]
              (when-not @answering?
                (reset! answering? true)
                (if (= value (:answer @challenge))
                  (do
                    (.notificationAsync Haptics (.-Success (.-NotificationFeedbackType Haptics)))
                    (reset! feedback :correct)
                    (js/setTimeout
                     (fn []
                       (if (= 2 @step)
                         (complete!)
                         (do (swap! step inc)
                             (reset! challenge (models/make-challenge @step))
                             (reset! feedback nil)
                             (reset! answering? false))))
                     550))
                  (do
                    (.notificationAsync Haptics (.-Error (.-NotificationFeedbackType Haptics)))
                    (reset! feedback :incorrect)
                    (js/setTimeout
                     (fn []
                       (reset! challenge (models/make-challenge @step))
                       (reset! feedback nil)
                       (reset! answering? false))
                     700)))))]
      [:> Modal {:visible true :animationType "fade" :presentationStyle "fullScreen"}
       [:> LinearGradient {:colors (clj->js [(theme/c :night950) (theme/c :night900) "#3C342C"])
                           :style (theme/js-style {:flex 1 :padding-horizontal 22 :padding-vertical 30})}
        [:> View {:style (theme/js-style {:align-items "center" :gap 14})}
         [theme/icon "sunny" 46 :moon]
         [:> Text {:style (theme/js-style {:font-size 34 :font-weight "900" :color (theme/c :text)})}
          "Bonjour"]
         [:> Text {:style (theme/js-style {:font-size 14 :text-align "center" :line-height 20
                                           :color (theme/c :muted)})}
          "Résolvez trois défis pour confirmer que vous êtes bien réveillé."]
         [:> View {:style (theme/js-style {:align-self "stretch"})} [progress @step]]]
        [:> View {:style (theme/js-style {:flex 1 :justify-content "center"})}
         [:> View {:style (theme/js-style {:padding 24 :gap 22 :border-radius 28
                                           :background-color "rgba(255,255,255,0.08)"
                                           :border-width 1 :border-color "rgba(245,207,135,0.25)"})}
          [:> Text {:style (theme/js-style {:text-align "center" :font-size 12 :font-weight "800"
                                            :letter-spacing 1.2 :color (theme/c :rose)})}
           (str "◉  " (str/upper-case (:kind @challenge)))]
          [:> Text {:style (theme/js-style {:text-align "center" :font-size 34 :line-height 43
                                            :font-weight "700" :color (theme/c :text)})}
           (:prompt @challenge)]
          [:> Text {:style (theme/js-style {:text-align "center" :font-size 14 :color (theme/c :muted)})}
           (:instruction @challenge)]
          [:> View {:style (theme/js-style {:flex-direction "row" :flex-wrap "wrap" :gap 12})}
           (for [option (:options @challenge)]
             ^{:key option}
             [:> Pressable {:disabled @answering? :onPress #(answer! option)
                            :style (fn [press]
                                     (theme/js-style {:width "48%" :min-height 58 :border-radius 17
                                                      :align-items "center" :justify-content "center"
                                                      :border-width 1 :border-color "rgba(255,255,255,0.1)"
                                                      :background-color (if (.-pressed press)
                                                                          "rgba(245,207,135,0.35)"
                                                                          "rgba(255,255,255,0.09)" )}))}
              [:> Text {:style (theme/js-style {:font-size 24 :font-weight "900" :color (theme/c :text)})}
               (str option)]])]
          (when @feedback
            [:> Text {:style (theme/js-style {:text-align "center" :font-size 14 :font-weight "700"
                                              :color (theme/c (if (= :correct @feedback) :mint :rose))})}
             (if (= :correct @feedback) "✓  Bien joué" "↻  Presque — nouveau défi")])]]
        [:> Text {:style (theme/js-style {:text-align "center" :font-size 12 :color (theme/c :muted)})}
         "L’alarme continue jusqu’à la résolution des trois défis."]]])))
