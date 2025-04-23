// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  devtools: { enabled: true },
  ssr: false,
  runtimeConfig: {
    public: {
      apiBaseUrl: process.env.NODE_ENV === 'development'
        ? 'http://localhost:8000/api'
        : '/api'
    }
  },
  router: {
    options: {
      hashMode: true,
      scrollBehaviorType: 'smooth'
    }
  },
  modules: [
    '@nuxt/icon',
    '@nuxt/fonts',
    '@nuxt/eslint',
    '@nuxt/image'
  ]
})