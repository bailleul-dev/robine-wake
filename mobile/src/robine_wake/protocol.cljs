(ns robine-wake.protocol
  (:require [goog.crypt :as crypt]
            [goog.crypt.base64 :as base64]))

(defn utf8-bytes [value]
  (js/Uint8Array. (clj->js (crypt/stringToUtf8ByteArray value))))

(defn bytes->string [bytes]
  (crypt/utf8ByteArrayToString (js->clj bytes)))

(defn bytes->base64 [bytes]
  (base64/encodeByteArray (js->clj bytes)))

(defn base64->bytes [value]
  (js/Uint8Array. (clj->js (base64/decodeStringToByteArray value))))

(defn uint16 [bytes offset]
  (+ (* (aget bytes offset) 256)
     (aget bytes (inc offset))))

(defn uint32 [bytes offset]
  (unsigned-bit-shift-right
   (+ (* (aget bytes offset) 16777216)
      (* (aget bytes (+ offset 1)) 65536)
      (* (aget bytes (+ offset 2)) 256)
      (aget bytes (+ offset 3))) 0))

(defn crc32 [bytes]
  (loop [index 0 crc 0xffffffff]
    (if (= index (.-length bytes))
      (unsigned-bit-shift-right (bit-xor crc 0xffffffff) 0)
      (let [start (bit-xor crc (aget bytes index))
            next-crc (loop [bit 0 value start]
                       (if (= bit 8)
                         value
                         (recur (inc bit)
                                (bit-xor (unsigned-bit-shift-right value 1)
                                         (if (odd? value) 0xedb88320 0)))))]
        (recur (inc index) next-crc)))))

(defn concat-bytes [left right]
  (let [result (js/Uint8Array. (+ (.-length left) (.-length right)))]
    (.set result left 0)
    (.set result right (.-length left))
    result))

(defn parse-page [value]
  (let [bytes (base64->bytes value)]
    (when (< (.-length bytes) 20)
      (throw (js/Error. "En-tête de réponse Bluetooth incomplet")))
    (when-not (and (= 0x52 (aget bytes 0)) (= 0x57 (aget bytes 1)) (= 1 (aget bytes 2)))
      (throw (js/Error. "En-tête de réponse Bluetooth invalide")))
    {:final? (= 1 (bit-and (aget bytes 3) 1))
     :sequence (uint32 bytes 4)
     :index (uint16 bytes 8)
     :count (uint16 bytes 10)
     :total (uint32 bytes 12)
     :crc (uint32 bytes 16)
     :payload (.slice bytes 20)}))
