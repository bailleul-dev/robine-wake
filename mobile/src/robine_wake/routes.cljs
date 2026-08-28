(ns robine-wake.routes
  (:require [clojure.string :as str]))

(def tab-routes
  {:morning {:path "/" :title "Matin · Robine Wake"}
   :evening {:path "/soir" :title "Soir · Robine Wake"}
   :alarms {:path "/alarmes" :title "Alarmes · Robine Wake"}
   :system {:path "/reveil" :title "Réveil · Robine Wake"}})

(def route-tabs
  {"/" :morning
   "/matin" :morning
   "/soir" :evening
   "/alarmes" :alarms
   "/reveil" :system})

(defn normalize-path [path]
  (let [path (if (str/blank? path) "/" path)]
    (if (and (> (count path) 1) (str/ends-with? path "/"))
      (subs path 0 (dec (count path)))
      path)))

(defn tab-for-path [path]
  (get route-tabs (normalize-path path)))

(defn path-for-tab [tab]
  (get-in tab-routes [tab :path] "/"))

(defn title-for-tab [tab]
  (get-in tab-routes [tab :title] "Robine Wake"))
