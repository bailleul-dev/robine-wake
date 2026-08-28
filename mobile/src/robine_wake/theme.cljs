(ns robine-wake.theme
  (:require [clojure.string :as str]
            [reagent.core :as r]
            ["react-native" :as rn]
            ["expo-linear-gradient" :refer [LinearGradient]]
            ["expo-glass-effect" :refer [GlassView isGlassEffectAPIAvailable]]
            ["@expo/vector-icons/Ionicons" :default Ionicons]))

(def colors
  {:night950 "#090812"
   :night900 "#151020"
   :night850 "#201627"
   :night800 "#2A1D30"
   :text "#FFF8F1"
   :muted "#BDB1BE"
   :moon "#F5CF87"
   :moon-soft "#FFE7B7"
   :lavender "#AAA7FF"
   :mint "#78D9BC"
   :rose "#FF8CA3"
   :breathing-inhale-amber "#F5B75B"
   :breathing-exhale-rose "#E0698F"
   :twilight-rose "#E0698F"})

(defn c [key] (get colors key))

(defn- camel-key [key]
  (if (keyword? key)
    (keyword (str/replace (name key) #"-([a-z])"
                          (fn [[_ letter]] (str/upper-case letter))))
    key))

(defn- react-native-style [value]
  (cond
    (map? value) (into {} (map (fn [[key nested]]
                                 [(camel-key key) (react-native-style nested)])) value)
    (vector? value) (mapv react-native-style value)
    (seq? value) (map react-native-style value)
    :else value))

(defn js-style [& maps]
  (clj->js (react-native-style (apply merge (remove nil? maps)))))

(def View (.-View rn))
(def Text (.-Text rn))
(def Pressable (.-Pressable rn))
(def ActivityIndicator (.-ActivityIndicator rn))
(def Dimensions (.-Dimensions rn))
(def Platform (.-Platform rn))
(def Animated (.-Animated rn))
(def AnimatedView (.-View Animated))

(def ios? (= "ios" (.-OS Platform)))
(def liquid-glass?
  (and ios?
       (try
         (isGlassEffectAPIAvailable)
         (catch :default _ false))))

;; Expo UI's SwiftUI entry point is native-only. Requiring it lazily keeps the
;; shared ClojureScript bundle usable by Expo Web while still rendering real
;; SwiftUI controls on iOS 26.
(def expo-ui (when liquid-glass? (js/require "@expo/ui/swift-ui")))
(def expo-ui-modifiers (when liquid-glass? (js/require "@expo/ui/swift-ui/modifiers")))
(def SwiftUIHost (when expo-ui (aget expo-ui "Host")))
(def SwiftUIButton (when expo-ui (aget expo-ui "Button")))

(def desktop-breakpoint 900)

(defonce viewport-width
  (r/atom (.-width (.get Dimensions "window"))))

(defonce dimensions-listener
  (.addEventListener Dimensions "change"
                     (fn [event]
                       (reset! viewport-width (.. event -window -width)))))

(defn desktop-width? [width]
  (>= width desktop-breakpoint))

(def stars
  [[8 7 2 0.42] [18 17 2 0.7] [31 5 1 0.55] [44 13 2 0.8]
   [62 6 2 0.5] [79 12 1 0.8] [91 4 2 0.55] [13 32 1 0.65]
   [72 27 2 0.48] [92 39 1 0.75] [25 53 2 0.4] [83 59 2 0.42]
   [6 70 1 0.65] [52 74 2 0.4] [94 83 1 0.65]])

(defn night-background []
  [:> LinearGradient
   {:colors (clj->js [(c :night950) (c :night900) "#211629"])
    :start #js {:x 0 :y 0}
    :end #js {:x 1 :y 1}
    :style (js-style {:position "absolute" :inset 0})}
   [:> View {:style (js-style {:position "absolute" :width 520 :height 520 :border-radius 999
                               :right -210 :top -260 :opacity 0.2
                               :background-color "#9D5C78"})}]
   [:> View {:style (js-style {:position "absolute" :width 480 :height 480 :border-radius 999
                               :left -260 :bottom -300 :opacity 0.13
                               :background-color "#E39A62"})}]
   (for [[x y size opacity] stars]
     ^{:key (str x "-" y)}
     [:> View {:style (js-style {:position "absolute" :left (str x "%") :top (str y "%")
                                 :width size :height size :border-radius size
                                 :opacity opacity :background-color (c :moon-soft)})}])])

(defn icon
  ([name] (icon name 20 :lavender))
  ([name size color]
   [:> Ionicons {:name name :size size :color (if (keyword? color) (c color) color)}]))

(defn crescent
  ([] (crescent 40))
  ([size]
   [:> View {:style (js-style {:shadow-color (c :moon) :shadow-opacity 0.35
                               :shadow-radius (* size 0.3)})}
    [icon "moon" size :moon]]))

(defn eyebrow
  ([text] (eyebrow text :lavender))
  ([text color]
   [:> Text {:style (js-style {:font-size 11 :font-weight "800" :letter-spacing 1.5
                               :color (c color) :text-transform "uppercase"})}
    text]))

(defn glass-panel [props & children]
  (let [style (:style props)
        fallback-background (or (:fallback-background props) "rgba(31,23,39,0.9)")]
    (if liquid-glass?
      (into [:> GlassView {:style (js-style style)
                           :glassEffectStyle (or (:effect props) "regular")
                           :tintColor (or (:tint props) "rgba(34,24,43,0.58)")
                           :colorScheme "dark"
                           :isInteractive (boolean (:interactive? props))}]
            children)
      (into [:> View {:style (js-style (assoc style :background-color fallback-background))}]
            children))))

(defn card [props & children]
  (let [highlighted (:highlighted props)
        padding (or (:padding props) 18)]
    (apply glass-panel
           {:effect (if highlighted "regular" "clear")
            :tint (if highlighted "rgba(84,54,69,0.58)" "rgba(35,27,45,0.48)")
            :fallback-background (if highlighted "rgba(49,33,49,0.95)" "rgba(31,23,39,0.9)")
            :style (merge {:padding padding :border-radius 24
                           :border-width 1
                           :border-color (if highlighted
                                           "rgba(245,207,135,0.32)"
                                           "rgba(255,231,183,0.12)")
                           :shadow-color "#2A1020" :shadow-opacity 0.3
                           :shadow-radius 18 :shadow-offset {:width 0 :height 10}}
                          (:style props))}
           children)))

(defn divider []
  [:> View {:style (js-style {:height 1 :background-color "rgba(255,255,255,0.08)"})}])

(def sf-symbols
  {"add" "plus"
   "refresh" "arrow.clockwise"
   "sunny" "sun.max.fill"
   "play" "play.fill"
   "flash" "bolt.fill"
   "stop" "stop.fill"})

(defn native-glass-button [{:keys [title on-press variant disabled icon-name compact grow]}]
  (let [primary? (= variant :primary)
        danger? (= variant :danger)
        ;; These modules are loaded dynamically so Expo Web never evaluates a
        ;; native-only entry point. String lookups also keep Closure Advanced
        ;; from renaming Expo UI's public JavaScript export names in releases.
        button-style (aget expo-ui-modifiers "buttonStyle")
        control-size (aget expo-ui-modifiers "controlSize")
        tint (aget expo-ui-modifiers "tint")
        disabled-modifier (aget expo-ui-modifiers "disabled")
        frame (aget expo-ui-modifiers "frame")
        modifiers (cond-> [(button-style (if primary? "glassProminent" "glass"))
                           (control-size (if compact "regular" "large"))
                           (tint (cond danger? (c :rose)
                                       primary? (c :moon)
                                       :else (c :moon-soft)))
                           (disabled-modifier (boolean disabled))]
                    grow (conj (frame #js {:maxWidth 10000})))]
    [:> SwiftUIHost
     {:matchContents (if grow #js {:vertical true :horizontal false} true)
      :colorScheme "dark"
      :seedColor (cond danger? (c :rose) primary? (c :moon) :else (c :moon-soft))
      :style (js-style {:min-height (if compact 38 48)
                        :flex (when grow 1)
                        :align-self (if grow "stretch" "center")})}
     [:> SwiftUIButton
      {:label title
       :systemImage (get sf-symbols icon-name)
       :role (if danger? "destructive" "default")
       :onPress on-press
       :modifiers (to-array modifiers)}]]))

(defn fallback-button [{:keys [title on-press variant disabled icon-name compact grow]}]
  (let [primary? (= variant :primary)
        danger? (= variant :danger)
        background (cond primary? (c :moon)
                         danger? "rgba(255,140,163,0.72)"
                         :else "rgba(255,231,183,0.08)")
        foreground (if primary? (c :night950) (c :text))]
    [:> Pressable
     {:accessibilityRole "button" :onPress on-press :disabled disabled
      :style (fn [state]
               (js-style {:flex-direction "row" :align-items "center" :justify-content "center"
                          :gap 7 :padding-horizontal (if compact 12 17)
                          :min-height (if compact 36 44) :padding-vertical (if compact 8 11)
                          :border-radius 999 :cursor (if disabled "default" "pointer")
                          :align-self (when grow "stretch")
                          :background-color background :border-width (if primary? 0 1)
                          :border-color "rgba(255,231,183,0.12)"
                          :opacity (cond disabled 0.45 (.-pressed state) 0.72 :else 1)
                          :transform [{:scale (if (.-pressed state) 0.97 1)}]}))}
     (when icon-name [icon icon-name (if compact 14 17) foreground])
     [:> Text {:style (js-style {:font-size (if compact 12 15) :font-weight "800" :color foreground})}
      title]]))

(defn button [props]
  (if liquid-glass?
    [native-glass-button props]
    [fallback-button props]))

(defn icon-button [{:keys [icon-name label on-press disabled color]
                    :or {color :lavender}}]
  [:> Pressable
   {:accessibilityRole "button" :accessibilityLabel label
    :onPress on-press :disabled disabled
    :style (fn [state]
             (js-style {:width 40 :height 40 :border-radius 13 :align-items "center"
                        :justify-content "center" :cursor (if disabled "default" "pointer")
                        :background-color (if (.-pressed state)
                                            "rgba(245,207,135,0.18)"
                                            "rgba(255,231,183,0.07)")
                        :border-width 1 :border-color "rgba(255,231,183,0.11)"
                        :opacity (if disabled 0.45 1)}))}
   [icon icon-name 20 color]])

(defn toggle [{:keys [value on-value-change disabled accessibility-label]}]
  (r/with-let [^js progress (new (.-Value Animated) (if value 1 0))]
    (let [_ (-> (.timing Animated progress
                         #js {:toValue (if value 1 0)
                              :duration 180
                              :useNativeDriver false})
                (.start))
          thumb-offset (.interpolate progress
                                     #js {:inputRange #js [0 1]
                                          :outputRange #js [0 22]})
          track-color (.interpolate progress
                                    #js {:inputRange #js [0 1]
                                         :outputRange #js ["#332B38" "#245448"]})
          border-color (.interpolate progress
                                     #js {:inputRange #js [0 1]
                                          :outputRange #js ["rgba(189,177,190,0.28)"
                                                            "rgba(120,217,188,0.56)"]})
          thumb-color (.interpolate progress
                                    #js {:inputRange #js [0 1]
                                         :outputRange #js ["#CFC3CC" "#A9E8D5"]})]
      [:> Pressable
       {:accessibilityRole "switch"
        :accessibilityLabel accessibility-label
        :accessibilityState (clj->js {:checked (boolean value) :disabled (boolean disabled)})
        :disabled disabled
        :hitSlop 8
        :onPress #(on-value-change (not value))
        :style (fn [press-state]
                 (js-style {:border-radius 999 :cursor (if disabled "default" "pointer")
                            :outline-style "none" :opacity (if disabled 0.42 1)
                            :transform [{:scale (if (.-pressed press-state) 0.96 1)}]}))}
       [:> AnimatedView
        {:style (js-style {:width 52 :height 30 :padding 3 :border-radius 999
                           :justify-content "center" :background-color track-color
                           :border-width 1 :border-color border-color})}
        [:> AnimatedView
         {:style (js-style {:width 22 :height 22 :border-radius 999
                            :background-color thumb-color
                            :shadow-color "#090812" :shadow-opacity 0.42
                            :shadow-radius 4 :shadow-offset {:width 0 :height 2}
                            :transform [{:translate-x thumb-offset}]})}]]])))

(defn input-style
  ([] (input-style {}))
  ([overrides]
   (js-style {:min-height 46 :padding-horizontal 14 :padding-vertical 11
              :border-radius 13 :border-width 1
              :border-color "rgba(255,231,183,0.15)"
              :font-size 14 :color (c :text)
              :background-color "rgba(13,9,18,0.58)"
              :outline-style "none"}
             overrides)))

(defn picker-style
  ([] (picker-style {}))
  ([overrides]
   (js-style {:min-height 46 :padding-horizontal 12 :border-radius 13
              :border-width 1 :border-color "rgba(255,231,183,0.15)"
              :color (c :text) :background-color (c :night800)
              :cursor "pointer"}
             overrides)))

(defn morning-sky [desktop? & children]
  [:> View {:style (js-style {:min-height (if desktop? 336 268) :overflow "hidden"
                              :border-radius (if desktop? 32 26) :border-width 1
                              :border-color "rgba(255,231,183,0.16)"
                              :shadow-color "#1D0D18" :shadow-opacity 0.45 :shadow-radius 30})}
   [:> LinearGradient
    {:colors (clj->js ["#3A263D" "#211B35" "#111425"])
     :start #js {:x 0 :y 0} :end #js {:x 1 :y 1}
     :style (js-style {:position "absolute" :inset 0})}]
   [:> LinearGradient
    {:colors (clj->js [(c :moon-soft) (c :moon) "#C67A58"])
     :start #js {:x 0.2 :y 0.1} :end #js {:x 0.9 :y 1}
     :style (js-style {:position "absolute" :width (if desktop? 190 142)
                       :height (if desktop? 190 142) :border-radius 999
                       :right (if desktop? -26 -38) :top (if desktop? -44 -24)
                       :opacity 0.94 :shadow-color (c :moon)
                       :shadow-opacity 0.5 :shadow-radius 48})}]
   [:> View {:style (js-style {:position "absolute" :left -50 :right -50
                               :bottom (if desktop? -105 -90) :height (if desktop? 205 170)
                               :border-radius 999 :background-color "rgba(41,42,69,0.96)"
                               :border-top-width 1 :border-top-color "rgba(255,255,255,0.09)"})}]
   [:> View {:style (js-style {:position "absolute" :left "18%" :right -90
                               :bottom (if desktop? -135 -112) :height (if desktop? 210 175)
                               :border-radius 999 :background-color "rgba(21,24,48,0.98)"})}]
   (into [:> View {:style (js-style {:flex 1 :z-index 2 :justify-content "center"
                                     :padding (if desktop? 28 18)})}]
         children)])

(defn status-pill [{:keys [title connected busy]}]
  [glass-panel {:effect "clear" :tint "rgba(52,39,60,0.42)"
                :fallback-background "rgba(255,255,255,0.07)"
                :style {:flex-direction "row" :align-items "center" :gap 7
                        :padding-horizontal 12 :padding-vertical 8 :border-radius 999
                        :border-width 1 :border-color "rgba(255,255,255,0.12)"}}
   (if busy
     [:> ActivityIndicator {:size "small" :color (c :moon)}]
     [:> View {:style (js-style {:width 7 :height 7 :border-radius 4
                                 :background-color (c (if connected :mint :rose))})}])
   [:> Text {:style (js-style {:font-size 12 :font-weight "700" :color (c :text)})}
    (if busy "Synchronisation" title)]])

(defn metric-row [{:keys [icon-name title detail color] :or {color :lavender}}]
  [:> View {:style (js-style {:flex-direction "row" :align-items "center" :gap 13})}
   [:> View {:style (js-style {:width 34 :height 34 :border-radius 10 :align-items "center"
                               :justify-content "center" :background-color "rgba(170,167,255,0.13)"})}
    [icon icon-name 18 color]]
   [:> Text {:style (js-style {:flex 1 :font-size 14 :font-weight "600" :color (c :text)})} title]
   [:> Text {:style (js-style {:font-size 14 :color (c :muted)})} detail]])

(defn screen-title [title action]
  (let [desktop? (:desktop? action)]
   [:> View {:style (js-style {:width "100%" :max-width (if desktop? 1180 nil)
                               :align-self "center" :flex-direction "row" :align-items "center"
                               :padding-horizontal (if desktop? 32 18)
                               :padding-top (if desktop? 28 8) :padding-bottom (if desktop? 20 14)})}
   [:> Text {:style (js-style {:flex 1 :font-size (if desktop? 34 30)
                               :font-weight "800" :color (c :text)})} title]
   (when action [button (assoc action :compact true)])]))
