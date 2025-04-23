document.addEventListener('DOMContentLoaded', function() {
    const form = document.getElementById('passwordChangeForm');
    const currentPassword = document.getElementById('currentPassword');
    const newPassword = document.getElementById('newPassword');
    const confirmPassword = document.getElementById('confirmPassword');
    const errorMessage = document.getElementById('errorMessage');
    const successMessage = document.getElementById('successMessage');
    const passwordStrength = document.getElementById('passwordStrength');
    
    // References to password requirement elements
    const lengthReq = document.getElementById('length');

    // If the user has been automatically redirected from the login page
    // because a password change is required
    const pendingUsername = sessionStorage.getItem('pendingUsername');
    const pendingPassword = sessionStorage.getItem('pendingPassword');
    
    if (pendingUsername && pendingPassword) {
        // Automatically fill in the current password field
        currentPassword.value = pendingPassword;
        
        // Show informational message
        errorMessage.textContent = 'You need to change your password to continue. Please choose a new password.';
        errorMessage.style.display = 'block';
        errorMessage.style.color = '#ff9800'; // Orange color to indicate warning, not error
    }

    // Function to validate password requirements based on Keycloak default policies
    function validatePassword(password) {
        const minLength = 8;
        
        // Update visual indicator for length requirement
        lengthReq.className = password.length >= minLength ? 'requirement valid' : 'requirement invalid';

        // Calculate password strength - simple version based on length
        let strengthText = '';
        let strengthColor = '';

        if (password.length < minLength) {
            strengthText = 'Weak';
            strengthColor = '#dc3545';
        } else if (password.length >= minLength && password.length < 12) {
            strengthText = 'Medium';
            strengthColor = '#ffc107';
        } else {
            strengthText = 'Strong';
            strengthColor = '#28a745';
        }

        passwordStrength.textContent = `Strength: ${strengthText}`;
        passwordStrength.style.color = strengthColor;

        // Password is valid if it meets the minimum length requirement
        return password.length >= minLength;
    }

    // Check password as user types
    newPassword.addEventListener('input', function() {
        validatePassword(this.value);
    });

    // Handle form submission
    form.addEventListener('submit', async function(e) {
        e.preventDefault();

        // Hide previous messages
        errorMessage.style.display = 'none';
        successMessage.style.display = 'none';

        // Validate that passwords match
        if (newPassword.value !== confirmPassword.value) {
            errorMessage.textContent = 'Passwords do not match';
            errorMessage.style.display = 'block';
            return;
        }

        // Validate password requirements
        if (!validatePassword(newPassword.value)) {
            errorMessage.textContent = 'The password must be at least 8 characters long';
            errorMessage.style.display = 'block';
            return;
        }

        // Prepare data
        const data = {
            current_password: currentPassword.value,
            new_password: newPassword.value
        };

        // Get CSRF token
        const csrfToken = getCookie('csrf_token');

        try {
            // Send request to server
            const response = await fetch('/api/auth/change-password', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken
                },
                body: JSON.stringify(data),
                credentials: 'same-origin'
            });

            const result = await response.json();

            if (!response.ok) {
                errorMessage.textContent = result.error || 'Error changing password';
                errorMessage.style.display = 'block';
                return;
            }

            // Show success message
            successMessage.textContent = result.message || 'Password changed successfully';
            successMessage.style.display = 'block';
            
            // Clear form
            form.reset();
            
            // Clear temporary data from sessionStorage
            sessionStorage.removeItem('pendingUsername');
            sessionStorage.removeItem('pendingPassword');
            
            // If there's a new CSRF token, update it
            if (result.csrf_token) {
                document.cookie = `csrf_token=${result.csrf_token}; path=/; secure; samesite=strict`;
                sessionStorage.setItem('csrfToken', result.csrf_token);
            }

            // Redirect to dashboard after 2 seconds
            setTimeout(() => {
                window.location.href = '#/';
            }, 2000);

        } catch (error) {
            console.error('Error:', error);
            errorMessage.textContent = 'Connection error. Please try again later.';
            errorMessage.style.display = 'block';
        }
    });

    // Helper function to get cookies
    function getCookie(name) {
        const value = `; ${document.cookie}`;
        const parts = value.split(`; ${name}=`);
        if (parts.length === 2) return parts.pop().split(';').shift();
        return '';
    }
});