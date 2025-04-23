<template>
  <div class="dashboard-page">
    <div class="header">
      <h1>Panel de Control</h1>
      <button @click="logout" class="logout-button">Cerrar sesión</button>
    </div>
    
    <div class="dashboard-content">
      <p>Bienvenido al panel de control. Tienes una sesión activa.</p>
      
      <!-- Aquí puedes añadir el contenido principal del dashboard -->
      <div class="dashboard-cards">
        <div class="card">
          <h3>Estadísticas</h3>
          <p>Contenido del panel de estadísticas</p>
        </div>
        
        <div class="card">
          <h3>Actividad Reciente</h3>
          <p>Contenido de actividades recientes</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { navigateTo } from '#app';

// Función para cerrar sesión
const logout = () => {
  // Eliminar el token CSRF del sessionStorage
  sessionStorage.removeItem('csrfToken');
  
  // Redirigir a la página de login
  navigateTo('/login');
};
</script>

<style scoped>
.dashboard-page {
  padding: 1rem;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 2rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid #eee;
}

.logout-button {
  background-color: #f44336;
  color: white;
  padding: 0.5rem 1rem;
  border: none;
  cursor: pointer;
}

.dashboard-cards {
  display: flex;
  gap: 1rem;
  flex-wrap: wrap;
}

.card {
  background-color: #f9f9f9;
  border-radius: 4px;
  padding: 1rem;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  flex: 1;
  min-width: 250px;
}
</style>