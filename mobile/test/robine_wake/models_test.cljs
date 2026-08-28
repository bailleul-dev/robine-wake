(ns robine-wake.models-test
  (:require [cljs.test :refer [deftest is testing]]
            [robine-wake.models :as models]))

(deftest alarm-payload-roundtrip
  (let [alarm {:id "alarm-1"
               :label "Semaine"
               :enabled true
               :local_time "06:45"
               :days_of_week [1 2 3 4 5]
               :timezone "Europe/Paris"
               :sound_id "rain"
               :strong_sound_id "storm"
               :prewake_seconds 1200
               :revision 4
               :volume_profile {:start 1 :ceiling 80 :ramp_seconds 1200}
               :snooze {:enabled true :duration_seconds 480 :maximum 3}}
        draft (models/alarm->draft alarm [])
        payload (models/draft->payload draft)]
    (is (= "06:45" (:local_time payload)))
    (is (= 1200 (:prewake_seconds payload)))
    (is (= 4 (:revision payload)))
    (is (= [1 2 3 4 5] (:days_of_week payload)))
    (is (models/draft-valid? draft))))

(deftest schedule-labels
  (is (= "En semaine" (models/schedule-label {:days_of_week [1 2 3 4 5]})))
  (is (= "Le week-end" (models/schedule-label {:days_of_week [6 7]})))
  (is (= "L · M · V" (models/schedule-label {:days_of_week [1 2 5]}))))

(deftest challenges-have-four-choices-and-the-answer
  (doseq [step (range 3)]
    (let [challenge (models/make-challenge step)]
      (is (= 4 (count (:options challenge))))
      (is (some #{(:answer challenge)} (:options challenge))))))
