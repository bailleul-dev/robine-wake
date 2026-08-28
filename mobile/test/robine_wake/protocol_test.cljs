(ns robine-wake.protocol-test
  (:require [cljs.test :refer [deftest is]]
            [robine-wake.protocol :as protocol]))

(defn put-uint16! [bytes offset value]
  (aset bytes offset (bit-and (unsigned-bit-shift-right value 8) 0xff))
  (aset bytes (inc offset) (bit-and value 0xff)))

(defn put-uint32! [bytes offset value]
  (doseq [index (range 4)]
    (aset bytes (+ offset index)
          (bit-and (unsigned-bit-shift-right value (* 8 (- 3 index))) 0xff))))

(deftest utf8-round-trip
  (let [message "Réveil — pluie 🌧️"
        bytes (protocol/utf8-bytes message)]
    (is (= message (protocol/bytes->string bytes)))
    (is (= message (protocol/bytes->string
                    (protocol/base64->bytes (protocol/bytes->base64 bytes)))))))

(deftest crc32-reference-vector
  (is (= 0xcbf43926 (protocol/crc32 (protocol/utf8-bytes "123456789")))))

(deftest parses-response-page
  (let [payload (protocol/utf8-bytes "{\"status\":\"ok\"}")
        checksum (protocol/crc32 payload)
        page-bytes (js/Uint8Array. (+ 20 (.-length payload)))]
    (aset page-bytes 0 0x52)
    (aset page-bytes 1 0x57)
    (aset page-bytes 2 1)
    (aset page-bytes 3 1)
    (put-uint32! page-bytes 4 42)
    (put-uint16! page-bytes 8 0)
    (put-uint16! page-bytes 10 1)
    (put-uint32! page-bytes 12 (.-length payload))
    (put-uint32! page-bytes 16 checksum)
    (.set page-bytes payload 20)
    (let [page (protocol/parse-page (protocol/bytes->base64 page-bytes))]
      (is (:final? page))
      (is (= 42 (:sequence page)))
      (is (= 0 (:index page)))
      (is (= 1 (:count page)))
      (is (= (.-length payload) (:total page)))
      (is (= checksum (:crc page)))
      (is (= "{\"status\":\"ok\"}" (protocol/bytes->string (:payload page)))))))
