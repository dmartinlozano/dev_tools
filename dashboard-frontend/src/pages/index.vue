<template>
  <div>
    <!-- Esta página redirige automáticamente a /login -->
  </div>
</template>

<script setup>
// Importar utilidad de navegación de Nuxt
import { navigateTo } from '#app';
import { onMounted } from 'vue';

// Redirigir a la página de login al montar el componente
onMounted(() => {
  navigateTo('/login');
});
</script>