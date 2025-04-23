from kube_client import KubeClient
from helm_client import HelmClient
from dev_tools_deployer import DevToolsDeployer
from installer.src.kube_client import set_namespace, set_secret, get_secret
from nicegui import ui
import os
import threading
import base64

kube_client = KubeClient()
helm_client = HelmClient()
dev_tools_deployer = DevToolsDeployer()

def set_background():
    ui.add_body_html('<script>document.body.style.background = "linear-gradient(135deg, #7ab8fc, #5ca2e0)";</script>')

@ui.page('/')
def index():
    set_background()
    with ui.card().classes('fixed-center'):

        ui.label('Welcome to Dev Tools installer').style('font-size: 2rem; font-weight: bold; text-align: center;')
        ui.label("Let's review your Kubernetes configuration")
        def on_next():

            releases = helm_client.list_releases()
            required_tools = ['cert-manager', 'ingress-nginx', 'vault', 'postgresql', 'keycloak', 'dashboard']
            deployed_tools = {}
            for tool in required_tools:
                deployed_tools[tool] = False
            for release in releases:
                if release['name'] in required_tools and release['status'] == 'deployed':
                    deployed_tools[release['name']] = True
            all_tools_deployed = all(deployed_tools.values())

            if all_tools_deployed:
                ui.navigate.to('/tools')
            elif dev_tools_deployer.mandatory_tools_step == 0:
                ui.navigate.to('/mandatory-tools-initial-installation')
            elif dev_tools_deployer.mandatory_tools_step == 1:
                ui.navigate.to('/mandatory-tools-progress-installation')
            else:
                ui.navigate.to('/tools')

        ui.button('Next', color="blue", on_click=on_next).style('align-self: flex-end')

@ui.page('/mandatory-tools-initial-installation')
def mandatory_tools_initial_installation():

    set_background()

    minikube_ip = os.environ.get("MINIKUBE_IP", "")
    minikube_dns = f"{minikube_ip}.nip.io" if minikube_ip else ""
    uploaded = {}

    def file_upload_handler(key):
        return lambda e: uploaded.update({key: e.content})
    
    with ui.card().style('min-width: 420px; max-width: 600px; width: 100%;').classes('fixed-center'):
        ui.label('Devtools configuration').style('font-size: 2rem; font-weight: bold; text-align: center; width: 100%;')
        base_dns = ui.input('Kubernetes domain', validation={'Domain is required': lambda v: bool(v)}, value=minikube_dns).props('outlined').classes('mb-2 w-full')
        admin_password = ui.input('Admin user password', password=True, validation={'Password is required': lambda v: bool(v)}).props('outlined').classes('mb-2 w-full')
        ui.label('Select the certificate type for your domain').classes('mb-2 w-full')
        cert_type = ui.radio(['letsencrypt', 'custom', 'selfsigned'], value='letsencrypt').classes('mb-2 w-full')
        admin_email = ui.input('Admin email').props('outlined').classes('mb-2 w-full').bind_visibility_from(cert_type, 'value', value='letsencrypt')
        for key, label in [('public_cert', 'Public certificate'), ('private_key', 'Private key'), ('ca_bundle', 'CA Bundle')]:
            ui.upload(label=label, on_upload=file_upload_handler(key)).classes('mb-2 w-full').bind_visibility_from(cert_type, 'value', value='custom')
        error = ui.label('').classes('text-red-500 text-xs mb-2 w-full')
        def submit():
            if not cert_type.value:
                error.set_text('Select a certificate type')
                return
            if cert_type.value == 'letsencrypt' and not admin_email.value:
                error.set_text('Email is required for Letsencrypt')
                return
            if cert_type.value == 'custom':
                for key, label in [('public_cert', 'Public certificate'), ('private_key', 'Private key'), ('ca_bundle', 'CA Bundle')]:
                    if not uploaded.get(key):
                        error.set_text(f'{label} is required')
                        return
            error.set_text('')
            form_data = {
                'base_dns': base_dns.value,
                'admin_password': admin_password.value,
                'cert_type': cert_type.value,
                'admin_email': admin_email.value,
                'public_cert': uploaded.get('public_cert'),
                'private_key': uploaded.get('private_key'),
                'ca_bundle': uploaded.get('ca_bundle'),
            }
            set_namespace()
            encoded_data = {k: base64.b64encode(v.encode()).decode('utf-8') if isinstance(v, str) and v is not None else v for k, v in form_data.items()}
            set_secret(
                secret_name="config",
                data=encoded_data
            )
            dev_tools_deployer.mandatory_tools_step = 1
            ui.navigate.to('/mandatory-tools-progress-installation')
        ui.button('Next', color="blue", on_click=submit).style('align-self: flex-end')

@ui.page('/mandatory-tools-progress-installation')
def mandatory_tools_progress_installation():
    set_background()
    if not dev_tools_deployer.is_installing:
        threading.Thread(target=dev_tools_deployer.install, daemon=True).start()
    with ui.card().style('min-width: 420px; max-width: 600px; width: 100%;').classes('fixed-center'):
        ui.label('Installing DevTools').style('font-size: 1.5rem; font-weight: bold; text-align: center; width: 100%;')
        progress_label = ui.label(dev_tools_deployer.progress_steps[-1] if dev_tools_deployer.progress_steps else 'Starting...').classes('mb-2')
        spinner = ui.spinner(size='sm').props('color=primary').style('align-self: flex-end')
        continue_button = ui.button('Next', color="blue", on_click=lambda: ui.navigate.to('/tools')).style('align-self: flex-end; display: none;')
        def update_progress():
            if dev_tools_deployer.progress_steps:
                progress_label.set_text(dev_tools_deployer.progress_steps[-1])
            if dev_tools_deployer.is_installing:
                spinner.set_visibility(True)
                continue_button.style('align-self: flex-end; display: none;')
            else:
                spinner.set_visibility(False)
                continue_button.style('align-self: flex-end; display: inline-block;')
                progress_label.set_text('Installation finished!')
                return False
            return True
        ui.timer(0.5, update_progress)

@ui.page('/tools')
def tools():
    set_background()
    with ui.card().classes('fixed-center'):
        ui.label('Dev Tools is ready').style('font-size: 2rem; font-weight: bold; text-align: center;')
        ui.label("Select an option:")
        secret = get_secret(secret_name="config")
        dns = secret['base_dns']
        ui.link(
            text='Open Keycloak',
            target=f'https://keycloak.{dns}',
            new_tab=True,
        )
        ui.link(
            text='Open Dashboard',
            target=f'https://dashboard.{dns}',
            new_tab=True,
        )

if __name__ in {"__main__", "__mp_main__"}:
    ui.run(
        port=8080,
        reload=True,
        title='Dev Tools Installer',
        favicon='https://nicegui.io/favicon.ico'
    )