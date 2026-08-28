(ns robine-wake.sse-test
  (:require [cljs.test :refer [deftest is]]
            [robine-wake.sse :as sse]))

(deftest derives-events-endpoint
  (is (= "/api/v1/events" (sse/events-endpoint "/api/v1/command")))
  (is (= "http://robine.local:4000/api/v1/events"
         (sse/events-endpoint "http://robine.local:4000/api/v1/command")))
  (is (= "http://robine.local:4000/api/v1/events"
         (sse/events-endpoint "http://robine.local:4000/api/v1/command?ignored=true")))
  (is (thrown-with-msg? js/Error #"Adresse Wi-Fi"
                        (sse/events-endpoint "http://robine.local:4000/state"))))

(deftest parses-sse-frames-across-network-chunks
  (let [first-pass (sse/consume-chunk "" "id: 41\r\nevent: state.changed\r\nda")
        second-pass (sse/consume-chunk (:buffer first-pass)
                                       "ta: {\"event\":\"state.changed\"}\r\n\r\n: keep-alive\r\n\r\n")]
    (is (empty? (:events first-pass)))
    (is (= [{:id "41"
             :event "state.changed"
             :data "{\"event\":\"state.changed\"}"}]
           (:events second-pass)))
    (is (= "" (:buffer second-pass)))))

(deftest joins-multiple-data-lines
  (is (= {:event "message" :data "hello\nworld"}
         (sse/parse-frame "data: hello\ndata: world"))))

(deftest preserves-crlf-split-between-network-chunks
  (let [first-pass (sse/consume-chunk "" "id: 9\r")
        second-pass (sse/consume-chunk (:buffer first-pass)
                                       "\nevent: session.changed\r\ndata: {}\r\n\r\n")]
    (is (empty? (:events first-pass)))
    (is (= [{:id "9" :event "session.changed" :data "{}"}]
           (:events second-pass)))))
