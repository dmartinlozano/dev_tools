<template>
  <div>
    <NuxtPage />
  </div>
</template>

<script setup>
import { onMounted } from 'vue';
import { navigateTo } from '#app';

// Al cargar la aplicación, verifica si existe un token CSRF
// y redirige a la página correspondiente
onMounted(() => {
  const csrfToken = sessionStorage.getItem('csrfToken');
  
  // Si no hay token, redirige a login, de lo contrario a dashboard
  if (!csrfToken) {
    navigateTo('/login');
  } else {
    navigateTo('/dashboard');
  }
});
</script>
