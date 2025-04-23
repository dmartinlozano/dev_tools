<template>
  <div class="login-container">
    <div class="login-card">
      <h1>Dev Tools</h1>
      <form @submit.prevent="login">
        <div class="form-group">
          <input type="text" id="username" placeholder="username or email" v-model="username" required />
        </div>
        <div class="form-group">
          <input type="password" id="password" placeholder="password" v-model="password" required />
        </div>
        <button type="submit">Sign In</button>
        <div v-if="errorMessage" class="error-message">
          {{ errorMessage }}
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { navigateTo } from '#app';

const username = ref('');
const password = ref('');
const errorMessage = ref('');

const login = async () => {
  try {
    // Limpiar mensaje de error previo
    errorMessage.value = '';
    
    const config = useRuntimeConfig()
    const response = await fetch(`${config.public.apiBaseUrl}/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        username: username.value,
        password: password.value,
      }),
      credentials: 'include'
    });
    
    if (!response.ok) {
      // Mostrar mensaje según el código de estado
      if (response.status === 401 || response.status === 403) {
        errorMessage.value = 'Incorrect credentials.';
      } else {
        errorMessage.value = 'Server error.';
      }
      return;
    }
    
    //navigateTo('/dashboard');
  } catch (error) {
    console.error('Error al iniciar sesión:', error);
    errorMessage.value = 'Server error.';
  }
};
</script>

<style>
/* Reset global para eliminar márgenes por defecto */
html, body {
  margin: 0;
  padding: 0;
  height: 100%;
  width: 100%;
  overflow: hidden;
}
</style>

<style scoped>
.login-container {
  height: 100vh;
  width: 100vw;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #7ab8fc, #5ca2e0);
  margin: 0;
  padding: 0;
  position: absolute;
  top: 0;
  left: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
}

.login-card {
  background-color: white;
  border-radius: 12px;
  box-shadow: 0 8px 24px rgba(54, 105, 149, 0.15);
  padding: 2.5rem;
  width: 100%;
  max-width: 360px;
  margin: 0 1rem;
}

h1 {
  color: #2979b5;
  margin-top: 0;
  margin-bottom: 1.5rem;
  text-align: center;
  font-size: 1.8rem;
}

.form-group {
  margin-bottom: 1.25rem;
}

label {
  display: block;
  color: #37474f;
  font-size: 0.9rem;
  margin-bottom: 0.5rem;
  font-weight: 500;
}

input[type="text"],
input[type="password"] {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid #e0e0e0;
  border-radius: 6px;
  color: #333;
  box-sizing: border-box;
  transition: border-color 0.2s;
}

input[type="text"]:focus,
input[type="password"]:focus {
  outline: none;
  border-color: #5ca2e0;
  box-shadow: 0 0 0 2px rgba(92, 162, 224, 0.2);
}

button {
  background-color: #5ca2e0;
  color: white;
  border: none;
  padding: 0.75rem;
  border-radius: 6px;
  font-weight: 600;
  width: 100%;
  cursor: pointer;
  transition: background-color 0.2s;
  margin-bottom: 1rem;
}

button:hover {
  background-color: #2979b5;
}

.error-message {
  color: #e53935;
  margin-bottom: 1rem;
  text-align: center;
  font-size: 0.9rem;
  background-color: rgba(229, 57, 53, 0.1);
  padding: 0.5rem;
  border-radius: 4px;
}
</style>