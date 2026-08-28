module.exports = ({ config }) => {
  const appleTeamId = process.env.APPLE_TEAM_ID;

  return {
    ...config,
    ios: {
      ...config.ios,
      ...(appleTeamId ? { appleTeamId } : {}),
    },
  };
};
