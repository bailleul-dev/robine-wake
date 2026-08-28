(ns robine-wake.store
  (:require [reagent.core :as r]))

(def initial-state
  {:tab :morning
   :connection :scanning
   :transport nil
   :http-endpoint nil
   :busy? false
   :error nil
   :alarms []
   :sounds []
   :device nil
   :recent-sessions []
   :active-session nil
   :smartphone-dismiss {:enabled true :locked false}
   :hue nil
   :hue-targets []
   :remote-button nil
   :breathing-synchronized-at nil
   :editor nil
   :challenge nil
   :last-updated nil})

(defonce app-state (r/atom initial-state))

(defn set-state! [path value]
  (swap! app-state assoc-in (if (sequential? path) path [path]) value))

(defn merge-state! [values]
  (swap! app-state merge values))

(defn clear-error! [] (set-state! :error nil))
