// main.js - Punto de entrada principal de la aplicación
import { initRouter } from './router.js';

// Función de inicialización asíncrona
async function init() {
    // Comprobar si hay sesión activa
    const csrfToken = sessionStorage.getItem('csrfToken');
    if (!csrfToken) {
        window.location.hash = '#/login';
    } else {
        window.location.hash = '#/dashboard';
    }
    
    // Inicializar el router
    await initRouter();
}

// Iniciar la aplicación cuando el DOM esté listo
document.addEventListener('DOMContentLoaded', init);