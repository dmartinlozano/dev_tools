document.addEventListener('DOMContentLoaded', function() {
    document.getElementById('next1Btn').addEventListener('click', async function() {
        const res = await fetch('/installer');
        const data = await res.json();
        if (data.length === 0) { //TODO check if ingress, cert-manager, vault, keycloak, dashboards are running
            document.getElementById('initDiv').style.display = 'none';
            document.getElementById('infoDiv').style.display = 'block';
            document.getElementById('progressLog').style.display = 'none';
            document.getElementById('finishDiv').style.display = 'none';
        }else{
            document.getElementById('initDiv').style.display = 'none';
            document.getElementById('infoDiv').style.display = 'none';
            document.getElementById('progressLog').style.display = 'none';
            document.getElementById('finishDiv').style.display = 'block';
        }
    });

    const certRadios = document.getElementsByName('certType');
    const adminEmailDiv = document.getElementById('adminEmailDiv');
    const customCertsDiv = document.getElementById('customCertsDiv');
    certRadios.forEach(radio => {
        radio.addEventListener('change', function() {
            if (this.value === 'letsencrypt') {
                adminEmailDiv.style.display = 'block';
                document.getElementById('adminEmail').setAttribute('required', 'required');
                customCertsDiv.style.display = 'none';
            } else if (this.value === 'custom') {
                adminEmailDiv.style.display = 'none';
                document.getElementById('adminEmail').removeAttribute('required');
                customCertsDiv.style.display = 'block';
            } else {
                adminEmailDiv.style.display = 'none';
                document.getElementById('adminEmail').removeAttribute('required');
                customCertsDiv.style.display = 'none';
            }
        });
    });

    document.getElementById('next2Btn').addEventListener('click', function(e) {
        let valid = true;
        const domain = document.getElementById('kubeDomain').value.trim();
        const domainError = document.getElementById('kubeDomainError');
        const domainRegex = /^(?!\*)([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$/;
        if (!domainRegex.test(domain)) {
            domainError.textContent = 'Enter a valid domain (no wildcards, e.g. example.com)';
            domainError.style.display = 'block';
            valid = false;
        } else {
            domainError.style.display = 'none';
        }

        const adminEmailDiv = document.getElementById('adminEmailDiv');
        const adminEmail = document.getElementById('adminEmail').value.trim();
        const adminEmailError = document.getElementById('adminEmailError');
        if (adminEmailDiv.style.display !== 'none' && document.querySelector('input[name="certType"]:checked')?.value === 'letsencrypt') {
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(adminEmail)) {
                adminEmailError.textContent = 'Enter a valid email address';
                adminEmailError.style.display = 'block';
                valid = false;
            } else {
                adminEmailError.style.display = 'none';
            }
        } else {
            adminEmailError.style.display = 'none';
        }

        // Custom certificates validation
        const certType = document.querySelector('input[name="certType"]:checked')?.value;
        const publicCertError = document.getElementById('publicCertError');
        const privateKeyError = document.getElementById('privateKeyError');
        const caBundleError = document.getElementById('caBundleError');
        publicCertError.style.display = 'none';
        privateKeyError.style.display = 'none';
        caBundleError.style.display = 'none';
        if (certType === 'custom') {
            const publicCert = document.getElementById('publicCert').files[0];
            const privateKey = document.getElementById('privateKey').files[0];
            const caBundle = document.getElementById('caBundle').files[0];
            if (!publicCert) {
                publicCertError.textContent = 'Public certificate is required';
                publicCertError.style.display = 'block';
                valid = false;
            }
            if (!privateKey) {
                privateKeyError.textContent = 'Private key is required';
                privateKeyError.style.display = 'block';
                valid = false;
            }
            if (!caBundle) {
                caBundleError.textContent = 'CA Bundle is required';
                caBundleError.style.display = 'block';
                valid = false;
            }
        }

        const adminPassword = document.getElementById('adminPassword').value.trim();
        const adminPasswordError = document.getElementById('adminPasswordError');
        if (!adminPassword) {
            adminPasswordError.textContent = 'Password is required';
            adminPasswordError.style.display = 'block';
            valid = false;
        } else {
            // Keycloak default: min 8 chars, 1 upper, 1 lower, 1 digit, 1 special
            const kcRegex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z\d]).{8,}$/;
            if (!kcRegex.test(adminPassword)) {
                adminPasswordError.textContent = 'Password must be at least 8 characters and include: one uppercase letter, one lowercase letter, one number, and one special character.';
                adminPasswordError.style.display = 'block';
                valid = false;
            } else {
                adminPasswordError.style.display = 'none';
            }
        }

        // Si no es válido, return;
        if (!valid) {
            return;
        }
        const formData = new FormData(document.getElementById('kubeForm'));
        fetch('/installer/prepare', {
            method: 'POST',
            body: formData
        })
        .then(async response => {
            const data = await response.json();
            if (!response.ok) {
                let msg = 'Unknown error';
                if (response.status === 409) {
                    msg = 'A configuration already exists and was replaced.';
                } else if (response.status === 500) {
                    msg = 'Internal server error: ' + (data.reason || '');
                } else if (data.reason) {
                    msg = data.reason;
                }
                showInstallerError(msg);
                return;
            }
            if (data.progress_id) {
                startProgress(data.progress_id);
            }else{
                msg = 'Internal server error ';
            }
        })
        .catch(error => {
            showInstallerError('Network or server error: ' + error);
        });
    });

    function startProgress(progress_id) {
        const progressDiv = document.getElementById('progressLog');
        const progressMessages = document.getElementById('progressMessages');
        progressMessages.innerHTML = '';
        document.getElementById('initDiv').style.display = 'none';
        document.getElementById('infoDiv').style.display = 'none';
        progressDiv.style.display = 'block';
        document.getElementById('finishDiv').style.display = 'none';
        const evtSource = new EventSource(`/installer/progress/${progress_id}`);
        evtSource.onmessage = function(event) {
            if (event.data === 'done') {
                evtSource.close();
                document.getElementById('next3Btn').style.display = 'none';
                //document.getElementById('finishDiv').style.display = 'block';
                return;
            }
            const msg = document.createElement('div');
            msg.textContent = event.data;
            progressMessages.appendChild(msg);
        };
    }

    function showInstallerError(msg) {
        let modal = document.getElementById('installerErrorModal');
        if (!modal) {
            modal = document.createElement('div');
            modal.id = 'installerErrorModal';
            modal.innerHTML = `
                <div class="fixed inset-0 flex items-center justify-center z-50 bg-black bg-opacity-40">
                    <div class="bg-white rounded-lg shadow-lg p-6 max-w-sm w-full text-center">
                        <h2 class="text-lg font-bold mb-2 text-red-600">Error</h2>
                        <p class="mb-4" id="installerErrorModalMsg"></p>
                        <button id="closeInstallerErrorModal" class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">Close</button>
                    </div>
                </div>
            `;
            document.body.appendChild(modal);
            document.getElementById('closeInstallerErrorModal').onclick = function() {
                modal.remove();
            };
        }
        document.getElementById('installerErrorModalMsg').textContent = msg || 'An unexpected error has occurred. Please try again later or contact support if the problem persists.';
        modal.style.display = 'flex';
    }
});
