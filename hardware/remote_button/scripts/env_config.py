Import("env")

import os


defines = []
for variable, macro in (
    ("ROBINE_WIFI_SSID", "WIFI_SSID"),
    ("ROBINE_WIFI_PASSPHRASE", "WIFI_PASSWORD"),
    ("REMOTE_BUTTON_WAKE_HOST", "WAKE_HOST"),
    ("REMOTE_BUTTON_ID", "REMOTE_BUTTON_ID"),
    ("REMOTE_BUTTON_SECRET_HEX", "REMOTE_BUTTON_SECRET_HEX"),
):
    value = os.environ.get(variable)
    if value:
        defines.append((macro, env.StringifyMacro(value)))

if defines:
    env.Append(CPPDEFINES=defines)
