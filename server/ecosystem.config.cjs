module.exports = {
  apps: [
    {
      name: "inhouse-maker-server-staging",
      cwd: __dirname,
      script: "dist/main.js",
      instances: Number(process.env.PM2_STAGING_INSTANCES || 1),
      exec_mode: "cluster",
      autorestart: true,
      watch: false,
      max_memory_restart: "500M",
      listen_timeout: 10000,
      kill_timeout: 5000,
      env: {
        NODE_ENV: "staging",
        APP_ENV: "staging",
      },
      env_staging: {
        NODE_ENV: "staging",
        APP_ENV: "staging",
      },
    },
    {
      name: "inhouse-maker-server-production",
      cwd: __dirname,
      script: "dist/main.js",
      instances: Number(process.env.PM2_PRODUCTION_INSTANCES || 1),
      exec_mode: "cluster",
      autorestart: true,
      watch: false,
      max_memory_restart: "750M",
      listen_timeout: 10000,
      kill_timeout: 5000,
      env: {
        NODE_ENV: "production",
        APP_ENV: "production",
      },
      env_production: {
        NODE_ENV: "production",
        APP_ENV: "production",
      },
    },
  ],
};
