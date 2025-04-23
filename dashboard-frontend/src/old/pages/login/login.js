// login.js
function handleLogin(event) {
  event.preventDefault();
  
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;
  const errorMessage = document.getElementById('error-message');
  
  errorMessage.classList.add('hidden');
  
  fetch('/api/auth/login', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      username,
      password
    }),
    credentials: 'include' // Important: include cookies in the request
  })
  .then(response => {
    if (!response.ok) {
      return response.json().then(errorData => {
        if (errorData.error === "redirect-to-change-password") {
          sessionStorage.setItem('pendingUsername', username);
          sessionStorage.setItem('pendingPassword', password);          
          window.location.replace('#/change-password');
        }else{
          throw new Error(errorData.error || 'Incorrect credentials');
        }
      });
    }
    return response.json();
  })
  .then(data => {
    sessionStorage.setItem('username', data.username);
    if (data.csrf_token) {
      sessionStorage.setItem('csrfToken', data.csrf_token);
    }
    
    window.location.replace('#/dashboard');
  })
  .catch(error => {
    if (error.message === 'redirect-to-change-password') {
      return;
    }
    
    errorMessage.textContent = error.message || 'Error to init session';
    errorMessage.classList.remove('hidden');
  });
}

// Helper function to make requests with CSRF protection
window.securedFetch = function(url, options = {}) {
  // Default configuration
  const defaultOptions = {
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': sessionStorage.getItem('csrfToken')
    }
  };
  
  // Combine options
  const fetchOptions = {
    ...defaultOptions,
    ...options,
    headers: {
      ...defaultOptions.headers,
      ...(options.headers || {})
    }
  };
  
  return fetch(url, fetchOptions);
};

function initLoginController() {
  const loginForm = document.getElementById('login-form');
  if (loginForm) {
    loginForm.addEventListener('submit', handleLogin);
  } else {
    // Form not found in the current page
  }
}

initLoginController();

if (typeof window !== 'undefined') {
  window.handleLogin = handleLogin;
  window.initLoginController = initLoginController;
}
