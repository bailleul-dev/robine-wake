(ns robine-wake.models
  (:require [clojure.string :as str]))

(def weekdays
  [{:id 1 :short "L" :name "Lundi"}
   {:id 2 :short "M" :name "Mardi"}
   {:id 3 :short "M" :name "Mercredi"}
   {:id 4 :short "J" :name "Jeudi"}
   {:id 5 :short "V" :name "Vendredi"}
   {:id 6 :short "S" :name "Samedi"}
   {:id 7 :short "D" :name "Dimanche"}])

(defn two-digits [value]
  (.padStart (str value) 2 "0"))

(defn local-time [hour minute]
  (str (two-digits hour) ":" (two-digits minute)))

(defn schedule-label [alarm]
  (let [days (set (:days_of_week alarm))]
    (cond
      (= days #{1 2 3 4 5}) "En semaine"
      (= days #{6 7}) "Le week-end"
      (= days #{1 2 3 4 5 6 7}) "Tous les jours"
      :else (->> weekdays
                 (filter #(contains? days (:id %)))
                 (map :short)
                 (str/join " · ")))))

(defn default-sound [sounds intensity fallback]
  (or (:id (first (filter #(= intensity (:intensity %)) sounds)))
      (:id (first sounds))
      fallback))

(defn alarm->draft [alarm sounds]
  (let [[hour minute] (map #(js/parseInt %) (str/split (or (:local_time alarm) "07:00") #":"))
        light (:light_profile alarm)]
    {:id (:id alarm)
     :label (or (:label alarm) "Mon réveil")
     :enabled (if (nil? alarm) true (:enabled alarm))
     :hour (or hour 7)
     :minute (or minute 0)
     :days (set (or (:days_of_week alarm) [1 2 3 4 5]))
     :timezone (or (:timezone alarm) (.-timeZone (.resolvedOptions (js/Intl.DateTimeFormat.)))
                   "Europe/Paris")
     :sound-id (or (:sound_id alarm) (default-sound sounds "gentle" "default"))
     :strong-sound-id (or (:strong_sound_id alarm) (default-sound sounds "strong" "default"))
     :start-volume (or (get-in alarm [:volume_profile :start]) 15)
     :ceiling-volume (or (get-in alarm [:volume_profile :ceiling]) 85)
     :prewake-minutes (max 1 (quot (or (:prewake_seconds alarm)
                                      (get-in alarm [:volume_profile :ramp_seconds])
                                      1200) 60))
     :snooze-enabled (if (nil? (get-in alarm [:snooze :enabled])) true (get-in alarm [:snooze :enabled]))
     :snooze-minutes (max 1 (quot (or (get-in alarm [:snooze :duration_seconds]) 480) 60))
     :snooze-maximum (or (get-in alarm [:snooze :maximum]) 3)
     :revision (:revision alarm)
     :light-enabled (boolean (:enabled light))
     :light-target-id (:target_id light)
     :light-target-name (:target_name light)
     :light-start-brightness (or (:start_brightness light) 1)
     :light-end-brightness (or (:end_brightness light) 70)
     :light-ramp-minutes (max 1 (quot (or (:ramp_seconds light) 900) 60))
     :light-end-behavior (or (:end_behavior light) "restore")}))

(defn draft-valid? [draft]
  (and (not (str/blank? (:label draft)))
       (seq (:days draft))
       (<= (:start-volume draft) (:ceiling-volume draft))
       (not (str/blank? (:sound-id draft)))
       (not (str/blank? (:strong-sound-id draft)))
       (or (not (:light-enabled draft)) (some? (:light-target-id draft)))))

(defn draft->payload [draft]
  (cond->
    {:label (str/trim (:label draft))
     :enabled (:enabled draft)
     :local_time (local-time (:hour draft) (:minute draft))
     :days_of_week (vec (sort (:days draft)))
     :timezone (:timezone draft)
     :sound_id (:sound-id draft)
     :strong_sound_id (:strong-sound-id draft)
     :prewake_seconds (* 60 (:prewake-minutes draft))
     :volume_profile {:start (:start-volume draft)
                      :ceiling (:ceiling-volume draft)
                      :ramp_seconds (* 60 (:prewake-minutes draft))}
     :light_profile (cond-> {:enabled (:light-enabled draft)
                             :start_brightness (:light-start-brightness draft)
                             :end_brightness (:light-end-brightness draft)
                             :ramp_seconds (* 60 (:light-ramp-minutes draft))
                             :end_behavior (:light-end-behavior draft)}
                      (:light-target-id draft) (assoc :target_id (:light-target-id draft))
                      (:light-target-name draft) (assoc :target_name (:light-target-name draft)))
     :dismiss_policy "manual"
     :snooze {:enabled (:snooze-enabled draft)
              :duration_seconds (* 60 (:snooze-minutes draft))
              :maximum (:snooze-maximum draft)}}
    (:revision draft) (assoc :revision (:revision draft))))

(defn random-choice [values]
  (nth values (js/Math.floor (* (count values) (js/Math.random)))))

(defn shuffled [values]
  (->> values (sort-by (fn [_] (js/Math.random))) vec))

(defn choices-around [answer]
  (loop [values #{answer}
         offsets (shuffled [-8 -6 -5 -4 -3 -2 -1 1 2 3 4 5 6 8])]
    (if (or (= 4 (count values)) (empty? offsets))
      (shuffled values)
      (recur (conj values (+ answer (first offsets))) (rest offsets)))))

(defn make-challenge [step]
  (case (mod step 3)
    0 (let [left (+ 14 (rand-int 25))
            right (+ 6 (rand-int 19))
            subtract? (< (js/Math.random) 0.5)
            answer (if subtract? (- left right) (+ left right))]
        {:kind "Calcul" :icon "calculator-outline"
         :prompt (str left " " (if subtract? "−" "+") " " right " = ?")
         :instruction "Choisissez le résultat"
         :answer answer :options (choices-around answer)})
    1 (let [start (+ 2 (rand-int 11))
            increment (+ 2 (rand-int 6))
            values (map #(+ start (* % increment)) (range 4))
            answer (+ start (* 4 increment))]
        {:kind "Suite logique" :icon "ellipsis-horizontal"
         :prompt (str (str/join "  ·  " values) "  ·  ?")
         :instruction "Quel nombre vient ensuite ?"
         :answer answer :options (choices-around answer)})
    (let [target (+ 3 (rand-int 6))
          amount (+ 2 (rand-int 3))
          other (repeatedly (- 7 amount)
                            #(loop [digit (+ 1 (rand-int 9))]
                               (if (= digit target) (recur (+ 1 (rand-int 9))) digit)))
          digits (shuffled (concat (repeat amount target) other))]
      {:kind "Attention" :icon "eye-outline"
       :prompt (str/join "  " digits)
       :instruction (str "Combien de fois voyez-vous le chiffre " target " ?")
       :answer amount :options (shuffled [1 2 3 4])})))
