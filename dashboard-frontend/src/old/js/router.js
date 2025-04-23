// router.js - Implementación de router en vanilla JavaScript

const routes = {
    '/login': 'login',
    '/dashboard': 'dashboard',
    '/usuarios': 'usuarios',
    '/change-password': 'password-change'
};

// Función para limpiar recursos previos
function cleanupPreviousResources() {
    document.querySelectorAll('script[data-controller], link[data-controller]').forEach(element => {
        element.parentNode.removeChild(element);
    });
}

// Función para cargar vistas
async function loadView(viewName) {
    // Limpiar recursos anteriores
    cleanupPreviousResources();
    
    try {
        // Cargar HTML
        const res = await fetch(`../pages/${viewName}/${viewName}.html`);
        const html = await res.text();
        
        document.getElementById('app').innerHTML = html;
        
        // Cargar recursos de forma asíncrona
        await new Promise(resolve => {
            setTimeout(async () => {
                // Cargar el archivo JS
                const script = document.createElement('script');
                script.type = 'module';
                script.src = `../pages/${viewName}/${viewName}.js`;
                script.setAttribute('data-controller', viewName);
                document.head.appendChild(script);
                
                // Cargar CSS
                const link = document.createElement('link');
                link.rel = 'stylesheet';
                link.href = `../pages/${viewName}/${viewName}.css`;
                link.setAttribute('data-controller', viewName);
                document.head.appendChild(link);
                
                resolve();
            }, 50);
        });
    } catch (error) {
        console.error(`Error cargando la vista ${viewName}:`, error);
    }
}

// Función para rutas protegidas
async function protectedRoute(viewName) {
    const csrfToken = sessionStorage.getItem('csrfToken');
    if (csrfToken) {
        await loadView(viewName);
    } else {
        window.location.hash = '#/login';
    }
}

// Función principal de enrutamiento
async function router() {
    // Obtener la ruta actual desde el hash
    const path = location.hash.slice(1) || '/';
    
    // Determinar qué vista cargar según la ruta
    if (path === '/login' || path === '/') {
        await loadView('login');
    } else if (path === '/dashboard') {
        await protectedRoute('dashboard');
    } else if (path === '/usuarios') {
        await protectedRoute('usuarios');
    } else if (path === '/change-password') {
        await protectedRoute('password-change');
    } else {
        // Ruta no encontrada
        console.error(`Ruta no encontrada: ${path}`);
        window.location.hash = '#/login';
    }
}

// Función para inicializar el router
function initRouter() {
    // Escuchar cambios en el hash para activar el enrutamiento
    window.addEventListener('hashchange', router);
    
    // Ejecutar el router inicialmente
    router();
}

// Exportar funciones necesarias
export { 
    router, 
    loadView, 
    protectedRoute, 
    cleanupPreviousResources, 
    initRouter 
};
