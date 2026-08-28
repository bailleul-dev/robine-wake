(ns robine-wake.sse
  (:require [clojure.string :as str]))

(def command-path "/api/v1/command")
(def events-path "/api/v1/events")

(defn events-endpoint [command-endpoint]
  (let [query-index (str/index-of command-endpoint "?")
        endpoint (if query-index (subs command-endpoint 0 query-index) command-endpoint)]
    (if (str/ends-with? endpoint command-path)
      (str (subs endpoint 0 (- (count endpoint) (count command-path))) events-path)
      (throw (js/Error. "Adresse Wi-Fi du réveil invalide")))))

(defn- field-value [line separator-index]
  (let [value (subs line (inc separator-index))]
    (if (str/starts-with? value " ") (subs value 1) value)))

(defn parse-frame [frame]
  (let [parsed
        (reduce
         (fn [event line]
           (if (or (str/blank? line) (str/starts-with? line ":"))
             event
             (let [separator-index (str/index-of line ":")
                   field (if separator-index (subs line 0 separator-index) line)
                   value (if separator-index (field-value line separator-index) "")]
               (case field
                 "event" (assoc event :event (if (str/blank? value) "message" value))
                 "data" (update event :data-lines conj value)
                 "id" (if (str/includes? value "\u0000") event (assoc event :id value))
                 event))))
         {:event "message" :data-lines []}
         (str/split frame #"\n"))]
    (when (seq (:data-lines parsed))
      (-> parsed
          (assoc :data (str/join "\n" (:data-lines parsed)))
          (dissoc :data-lines)))))

(defn consume-chunk [buffer chunk]
  (let [combined (str buffer chunk)
        trailing-cr? (str/ends-with? combined "\r")
        complete (if trailing-cr? (subs combined 0 (dec (count combined))) combined)
        normalized (-> complete
                       (str/replace "\r\n" "\n")
                       (str/replace "\r" "\n")
                       (str (when trailing-cr? "\r")))]
    (loop [remaining normalized
           events []]
      (let [separator-index (str/index-of remaining "\n\n")]
        (if (nil? separator-index)
          {:buffer remaining :events events}
          (let [frame (subs remaining 0 separator-index)
                event (parse-frame frame)]
            (recur (subs remaining (+ separator-index 2))
                   (cond-> events event (conj event)))))))))
