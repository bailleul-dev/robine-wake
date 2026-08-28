#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <U8g2lib.h>
#include <WiFi.h>
#include <time.h>

#include "robine_sprites.h"

#if __has_include("local_config.h")
#include "local_config.h"
#endif

#ifndef WIFI_SSID
#define WIFI_SSID ""
#endif

#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD ""
#endif

#ifndef WAKE_HOST
#define WAKE_HOST "robine-wake.local"
#endif

#ifndef STOP_BUTTON_PIN
#define STOP_BUTTON_PIN 0
#endif

namespace {
constexpr uint8_t kOledClock = 15;
constexpr uint8_t kOledData = 4;
constexpr uint8_t kOledReset = 16;
constexpr uint32_t kWakeStateIntervalMs = 2000;
constexpr uint32_t kWifiRetryIntervalMs = 8000;
constexpr uint32_t kFeedbackDurationMs = 3000;
constexpr uint32_t kDebounceMs = 45;
constexpr uint32_t kDebugHoldDurationMs = 3000;
constexpr uint32_t kDebugPreviewDurationMs = 15000;
constexpr uint32_t kStartupBrightDurationMs = 1500;
constexpr uint32_t kInteractionBrightDurationMs = 5000;
constexpr uint8_t kIdleContrast = 16;
constexpr uint8_t kActiveContrast = 255;

enum class Feedback { none, dismissed, idle, network_error, server_error };

// VCOMH0 gives the SSD1306 its full contrast range. The default constructor
// keeps the panel bias high enough that contrast 0 and 255 look very similar.
U8G2_SSD1306_128X64_VCOMH0_F_SW_I2C display(
    U8G2_R0, kOledClock, kOledData, kOledReset);

Feedback feedback = Feedback::none;
uint32_t feedbackStartedAt = 0;
uint32_t lastWakeStateCheckAt = 0;
uint32_t lastWifiAttemptAt = 0;
uint32_t lastFrameAt = 0;
uint32_t buttonChangedAt = 0;
uint32_t buttonPressedAt = 0;
uint32_t brightUntilAt = 0;
uint32_t debugPreviewUntilAt = 0;
bool wakeReachable = false;
bool wakeActive = false;
bool previousButton = true;
bool buttonArmed = false;
bool buttonActionHandled = false;
bool wifiWasConnected = false;
uint8_t appliedContrast = 255;

bool debugPreviewActive() {
  return static_cast<int32_t>(debugPreviewUntilAt - millis()) > 0;
}

bool shouldShowAlarmScreen() {
  return wakeActive || debugPreviewActive();
}

void updateDisplayContrast() {
  bool bright = shouldShowAlarmScreen() ||
                static_cast<int32_t>(brightUntilAt - millis()) > 0;
  uint8_t target = bright ? kActiveContrast : kIdleContrast;
  if (target == appliedContrast) return;
  display.setContrast(target);
  appliedContrast = target;
}

String localTimeText() {
  struct tm value;
  if (!getLocalTime(&value, 5)) return "--:--";
  char output[6];
  strftime(output, sizeof(output), "%H:%M", &value);
  return String(output);
}

void drawWifiBars(int16_t x, int16_t y, int32_t rssi) {
  uint8_t strength = rssi > -58 ? 4 : rssi > -67 ? 3 : rssi > -76 ? 2 : 1;
  for (uint8_t index = 0; index < 4; ++index) {
    uint8_t height = 2 + index * 2;
    if (index < strength) display.drawBox(x + index * 4, y - height, 2, height);
  }
}

void drawPressArrow(uint8_t phase) {
  int8_t bounce = phase == 1 || phase == 3 ? -1 : 1;
  // Unambiguous left-pointing arrow, animated horizontally toward the button.
  int16_t x = 2 + bounce;
  display.drawTriangle(x, 7, x + 7, 1, x + 7, 13);
  display.drawBox(x + 6, 5, 10, 5);
}

void drawHeart(int16_t x, int16_t y, bool large) {
  display.drawPixel(x + 1, y);
  display.drawPixel(x + 3, y);
  display.drawHLine(x, y + 1, 5);
  display.drawHLine(x + 1, y + 2, 3);
  display.drawPixel(x + 2, y + 3);
  if (large) {
    display.drawPixel(x, y + 2);
    display.drawPixel(x + 4, y + 2);
  }
}

void drawActiveAlarmScreen() {
  uint8_t phase = (millis() / 180) % kRobineFrameCount;
  display.clearBuffer();
  display.setDrawColor(1);
  drawPressArrow(phase);

  display.setFont(u8g2_font_5x8_tf);
  display.drawUTF8(25, 8, "JE T'AIME,");

  int8_t runOffset = phase == 1 ? -1 : phase == 3 ? 1 : 0;
  display.drawXBMP(38 + runOffset, 10, kRobineSpriteWidth,
                   kRobineSpriteHeight, kRobineFrames[phase]);

  // The hearts float around Robine instead of being fixed to the dog sprite.
  drawHeart(21, 19 + (phase % 2), phase == 0 || phase == 3);
  drawHeart(101, 14 - (phase % 2), phase == 1 || phase == 2);
  if (phase == 2) drawHeart(111, 30, false);

  display.setFont(u8g2_font_5x8_tf);
  const char* message = "TU ME PROMÈNES";
  int16_t messageX = (128 - display.getUTF8Width(message)) / 2;
  display.drawUTF8(messageX, 63, message);
  display.sendBuffer();
}

void drawMainScreen() {
  if ((wakeReachable && wakeActive) || debugPreviewActive()) {
    drawActiveAlarmScreen();
    return;
  }

  display.clearBuffer();
  display.setDrawColor(1);
  display.setFont(u8g2_font_6x12_tf);
  display.drawStr(2, 10, "ROBINe WAKE");

  if (WiFi.status() == WL_CONNECTED) {
    drawWifiBars(112, 10, WiFi.RSSI());
  } else {
    display.drawLine(114, 2, 124, 10);
    display.drawLine(124, 2, 114, 10);
  }

  display.setFont(u8g2_font_logisoso24_tn);
  String time = localTimeText();
  display.drawStr(2, 40, time.c_str());

  display.setFont(u8g2_font_6x12_tf);
  if (WiFi.status() != WL_CONNECTED) {
    display.drawStr(88, 25, "WI-FI");
    display.drawStr(88, 38, "EN COURS");
  } else if (wakeReachable) {
    display.drawDisc(94, 21, 3);
    display.drawStr(101, 25, "PRET");
    display.drawStr(88, 38, "REVEIL");
  } else {
    display.drawCircle(94, 21, 3);
    display.drawStr(101, 25, "HORS");
    display.drawStr(88, 38, "LIGNE");
  }

  display.drawRBox(0, 50, 128, 14, 3);
  display.setDrawColor(0);
  display.setFont(u8g2_font_6x12_tf);
  display.drawStr(17, 61, "PRG  ARRETER");
  display.setDrawColor(1);
  display.sendBuffer();
}

void drawCheck(uint8_t x, uint8_t y) {
  display.drawCircle(x, y, 11);
  display.drawLine(x - 6, y, x - 2, y + 5);
  display.drawLine(x - 2, y + 5, x + 7, y - 6);
  display.drawLine(x - 6, y + 1, x - 2, y + 6);
  display.drawLine(x - 2, y + 6, x + 7, y - 5);
}

void drawAlert(uint8_t x, uint8_t y) {
  display.drawCircle(x, y, 11);
  display.drawBox(x - 1, y - 6, 2, 8);
  display.drawDisc(x, y + 6, 1);
}

void drawFeedbackScreen(const char* eyebrow, const char* title, const char* detail,
                        bool success) {
  display.clearBuffer();
  success ? drawCheck(15, 22) : drawAlert(15, 22);
  display.setFont(u8g2_font_5x8_tf);
  display.drawStr(33, 9, eyebrow);
  display.setFont(u8g2_font_helvB10_tf);
  display.drawStr(33, 25, title);
  display.setFont(u8g2_font_5x8_tf);
  display.drawStr(33, 39, detail);
  display.drawRBox(0, 50, 128, 14, 3);
  display.setDrawColor(0);
  display.drawStr(19, 60, "RETOUR AUTOMATIQUE");
  display.setDrawColor(1);
  display.sendBuffer();
}

void render() {
  if (feedback != Feedback::none && millis() - feedbackStartedAt >= kFeedbackDurationMs) {
    feedback = Feedback::none;
  }

  switch (feedback) {
    case Feedback::dismissed:
      drawFeedbackScreen("COMMANDE ENVOYEE", "Reveil arrete", "Bonne journee", true);
      break;
    case Feedback::idle:
      drawFeedbackScreen("TOUT EST CALME", "Aucun reveil", "Rien a arreter", true);
      break;
    case Feedback::network_error:
      drawFeedbackScreen("HORS CONNEXION", "Wi-Fi absent", "Nouvel essai auto", false);
      break;
    case Feedback::server_error:
      drawFeedbackScreen("PAS DE REPONSE", "Reveil hors ligne", "Verifier Raspberry", false);
      break;
    case Feedback::none:
      drawMainScreen();
      break;
  }
}

bool pollWakeState() {
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClient client;
  HTTPClient request;
  request.setConnectTimeout(700);
  request.setTimeout(1500);
  if (!request.begin(client, "http://" WAKE_HOST ":4000/api/v1/command")) return false;

  request.addHeader("Content-Type", "application/json");
  int statusCode = request.POST("{\"v\":1,\"op\":\"session.get\",\"body\":{}}");
  String response = statusCode > 0 ? request.getString() : String();
  request.end();

  JsonDocument result;
  bool ready = statusCode == HTTP_CODE_OK &&
               deserializeJson(result, response) == DeserializationError::Ok &&
               result["status"] == "ok";
  wakeActive = ready && !result["body"]["active_session"].isNull();
  Serial.printf("Wake state: %s%s\n", ready ? "ready" : "offline",
                wakeActive ? ", alarm active" : "");
  updateDisplayContrast();
  return ready;
}

Feedback dismissAlarm() {
  if (WiFi.status() != WL_CONNECTED) return Feedback::network_error;

  WiFiClient client;
  HTTPClient request;
  request.setConnectTimeout(1200);
  request.setTimeout(2500);
  if (!request.begin(client, "http://" WAKE_HOST ":4000/api/v1/command")) {
    return Feedback::server_error;
  }

  request.addHeader("Content-Type", "application/json");
  String requestId = "screen-" + String(static_cast<uint32_t>(ESP.getEfuseMac())) + "-" +
                     String(millis());
  JsonDocument command;
  command["v"] = 1;
  command["id"] = requestId;
  command["op"] = "session.dismiss";
  command["body"].to<JsonObject>();
  String payload;
  serializeJson(command, payload);

  int statusCode = request.POST(payload);
  String response = statusCode > 0 ? request.getString() : String();
  request.end();
  if (statusCode != HTTP_CODE_OK) return Feedback::server_error;

  JsonDocument result;
  if (deserializeJson(result, response) != DeserializationError::Ok) {
    return Feedback::server_error;
  }
  if (result["status"] == "ok") {
    wakeActive = false;
    return Feedback::dismissed;
  }
  if (result["error"]["code"] == "no_active_session") return Feedback::idle;
  return Feedback::server_error;
}

void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  lastWifiAttemptAt = millis();
  WiFi.disconnect(false, false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.println("Connecting to Wi-Fi...");
}

void handleButton() {
  bool currentButton = digitalRead(STOP_BUTTON_PIN) != LOW;

  if (!buttonArmed) {
    previousButton = currentButton;
    buttonArmed = currentButton;
    return;
  }

  if (currentButton != previousButton && millis() - buttonChangedAt >= kDebounceMs) {
    buttonChangedAt = millis();
    previousButton = currentButton;
    if (!currentButton) {
      buttonPressedAt = millis();
      buttonActionHandled = false;
      brightUntilAt = millis() + kInteractionBrightDurationMs;
      updateDisplayContrast();
      // A real alarm must stop immediately; never make a sleepy user wait for
      // long-press detection. At rest, defer the short-press action to release.
      if (wakeActive) {
        buttonActionHandled = true;
        feedback = dismissAlarm();
        feedbackStartedAt = millis();
        wakeReachable = feedback != Feedback::network_error &&
                        feedback != Feedback::server_error;
        Serial.printf("Dismiss result: %u\n", static_cast<unsigned>(feedback));
        render();
      }
    } else if (!buttonActionHandled) {
      buttonActionHandled = true;
      feedback = dismissAlarm();
      feedbackStartedAt = millis();
      wakeReachable = feedback != Feedback::network_error &&
                      feedback != Feedback::server_error;
      Serial.printf("Dismiss result: %u\n", static_cast<unsigned>(feedback));
      render();
    }
  }

  if (!currentButton && !buttonActionHandled &&
      millis() - buttonPressedAt >= kDebugHoldDurationMs) {
    buttonActionHandled = true;
    debugPreviewUntilAt = millis() + kDebugPreviewDurationMs;
    feedback = Feedback::none;
    updateDisplayContrast();
    Serial.println("Alarm screen debug preview");
    render();
  }
}

void trackWifi() {
  bool connected = WiFi.status() == WL_CONNECTED;
  if (connected && !wifiWasConnected) {
    Serial.printf("Wi-Fi connected: %s\n", WiFi.localIP().toString().c_str());
    wakeReachable = pollWakeState();
  } else if (!connected && wifiWasConnected) {
    Serial.println("Wi-Fi disconnected");
    wakeReachable = false;
  }
  wifiWasConnected = connected;
}
}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(STOP_BUTTON_PIN, INPUT_PULLUP);
  display.begin();
  brightUntilAt = millis() + kStartupBrightDurationMs;
  updateDisplayContrast();

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(false);
  WiFi.setSleep(false);
  configTzTime("CET-1CEST,M3.5.0,M10.5.0/3", "pool.ntp.org", "time.cloudflare.com");
  connectWifi();
  render();
}

void loop() {
  handleButton();
  trackWifi();
  updateDisplayContrast();

  if (WiFi.status() != WL_CONNECTED && millis() - lastWifiAttemptAt >= kWifiRetryIntervalMs) {
    connectWifi();
  }
  if (millis() - lastWakeStateCheckAt >= kWakeStateIntervalMs) {
    lastWakeStateCheckAt = millis();
    wakeReachable = pollWakeState();
  }
  uint32_t frameIntervalMs = shouldShowAlarmScreen() ? 180 : 1000;
  if (millis() - lastFrameAt >= frameIntervalMs) {
    lastFrameAt = millis();
    render();
  }
  delay(8);
}
