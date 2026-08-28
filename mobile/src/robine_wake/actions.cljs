(ns robine-wake.actions
  (:require [robine-wake.models :as models]
            [robine-wake.store :as store]
            [robine-wake.transport :as transport]))

(defn edit-alarm! [alarm]
  (store/set-state! :editor (models/alarm->draft alarm (:sounds @store/app-state))))

(defn create-alarm! []
  (let [draft (models/alarm->draft nil (:sounds @store/app-state))
        first-target (first (:hue-targets @store/app-state))]
    (store/set-state!
     :editor
     (if first-target
       (assoc draft :light-enabled true
                    :light-target-id (:id first-target)
                    :light-target-name (:name first-target))
       draft))))

(defn close-editor! [] (store/set-state! :editor nil))

(defn save-alarm! [draft]
  (let [payload (models/draft->payload draft)]
    (close-editor!)
    (if-let [id (:id draft)]
      (transport/command! "alarm.update" {:alarm_id id :alarm payload})
      (transport/command! "alarm.create" {:alarm payload}))))

(defn delete-alarm! [alarm]
  (transport/command! "alarm.delete" {:alarm_id (:id alarm) :revision (:revision alarm)}))

(defn set-alarm-enabled! [alarm enabled]
  (let [draft (assoc (models/alarm->draft alarm (:sounds @store/app-state)) :enabled enabled)]
    (transport/command! "alarm.update" {:alarm_id (:id alarm)
                                         :alarm (models/draft->payload draft)})))

(defn trigger-alarm! [id] (transport/command! "alarm.trigger" {:alarm_id id}))
(defn trigger-strong! [id] (transport/command! "alarm.trigger_strong" {:alarm_id id}))
(defn snooze! [] (transport/command! "session.snooze"))
(defn dismiss! [] (transport/command! "session.dismiss"))
(defn set-smartphone-dismiss! [enabled]
  (transport/command! "settings.smartphone_dismiss.set" {:enabled enabled}))
(defn confirm-clock! [] (transport/command! "clock.confirm"))
(defn erase-history! [] (transport/command! "history.erase"))
(defn pair-hue! [host] (transport/command! "hue.pair" {:bridge_host host}))
(defn refresh-hue! [] (transport/command! "hue.refresh"))
(defn disconnect-hue! [] (transport/command! "hue.disconnect"))
(defn start-breathing! [target duration volume]
  (transport/command! "breathing.start" {:target_id target
                                           :duration_minutes duration
                                           :volume_percent volume}))
(defn breathing-volume! [volume]
  (transport/command! "breathing.volume" {:volume_percent volume}))
(defn stop-breathing! [] (transport/command! "breathing.stop"))
(defn begin-button-pairing! []
  (transport/command! "remote_button.pairing.begin" {:duration_seconds 120}))
(defn remove-button! [id]
  (transport/command! "remote_button.remove" {:button_id id}))
