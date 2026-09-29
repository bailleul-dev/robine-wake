module.exports = ({ config }) => {
  const appleTeamId = process.env.APPLE_TEAM_ID;
  const androidVersionCode = Number.parseInt(process.env.ANDROID_VERSION_CODE ?? "", 10);

  return {
    ...config,
    ios: {
      ...config.ios,
      ...(appleTeamId ? { appleTeamId } : {}),
    },
    android: {
      ...config.android,
      ...(Number.isInteger(androidVersionCode) ? { versionCode: androidVersionCode } : {}),
    },
  };
};
