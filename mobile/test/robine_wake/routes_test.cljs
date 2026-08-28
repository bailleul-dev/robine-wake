(ns robine-wake.routes-test
  (:require [cljs.test :refer [deftest is]]
            [robine-wake.routes :as routes]))

(deftest maps-public-paths-to-tabs
  (is (= :morning (routes/tab-for-path "/")))
  (is (= :morning (routes/tab-for-path "/matin")))
  (is (= :evening (routes/tab-for-path "/soir/")))
  (is (= :alarms (routes/tab-for-path "/alarmes")))
  (is (= :system (routes/tab-for-path "/reveil")))
  (is (nil? (routes/tab-for-path "/inconnue"))))

(deftest maps-tabs-to-canonical-paths-and-titles
  (is (= "/" (routes/path-for-tab :morning)))
  (is (= "/soir" (routes/path-for-tab :evening)))
  (is (= "/alarmes" (routes/path-for-tab :alarms)))
  (is (= "/reveil" (routes/path-for-tab :system)))
  (is (= "Réveil · Robine Wake" (routes/title-for-tab :system))))
