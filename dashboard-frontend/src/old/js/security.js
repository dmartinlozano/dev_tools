function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
    return null;
}

function setupTokenRefresher() {
  setInterval(checkAndRefreshToken, 4 * 60 * 1000);
  monitorFetchForAuthErrors();
}

function checkAndRefreshToken() {
  refreshAuthToken()
    .then(success => {
      if (success) {
        console.log('Token automatically renewed');
      }
    })
    .catch(error => {
      console.error('Error refreshing token:', error);
      if (window.location.hash !== '#/login') {
        window.location.replace('#/login');
      }
    });
}

function refreshAuthToken() {
  const isDevelopment = window.location.hostname.includes('nip.io');
  const fetchOptions = {
    method: 'POST',
    credentials: 'include'
  };

  return fetch('/api/auth/refresh', fetchOptions)
  .then(response => {
    if (!response.ok) {
      throw new Error('Could not refresh token');
    }
    return response.json();
  })
  .then(data => {
    if (data.csrf_token) {
      sessionStorage.setItem('csrfToken', data.csrf_token);
    }
    return true;
  })
  .catch(error => {
    // Si estamos en desarrollo y hay un error de certificado, mostramos una alerta instructiva
    if (isDevelopment && error.message.includes('Failed to fetch')) {
      console.warn('Error de certificado detectado. En desarrollo, necesitas aceptar el certificado autofirmado navegando manualmente a https://devtools.192.168.49.2.nip.io y aceptando el certificado.');
    }
    throw error;
  });
}

function monitorFetchForAuthErrors() {
  const originalFetch = window.fetch;
  
  window.fetch = function(url, options = {}) {
    return originalFetch(url, options)
      .then(response => {
        if (response.status === 401 || response.status === 403) {
          if (!url.includes('/api/auth/refresh') && !url.includes('/api/auth/login')) {
            return refreshAuthToken()
              .then(success => {
                if (success) {
                  if (options.headers && options.headers['X-CSRF-Token']) {
                    options.headers['X-CSRF-Token'] = sessionStorage.getItem('csrfToken');
                  }
                  return originalFetch(url, options);
                }
                return response;
              })
              .catch(() => {
                return response;
              });
          }
        }
        return response;
      });
  };
}

document.addEventListener('DOMContentLoaded', function() {
    setupTokenRefresher();
});
  

if (typeof window !== 'undefined') {
  window.refreshAuthToken = refreshAuthToken;
  window.setupTokenRefresher = setupTokenRefresher;
  window.getCookie = getCookie;
}

