from nicegui import ui
import requests
import os

base_dns = None
cert_type = None
    
def set_background():
    ui.add_body_html('<script>document.body.style.background = "linear-gradient(135deg, #7ab8fc, #5ca2e0)";</script>')

@ui.page('/login')
def login():
    set_background()
    ui.label('Login').style('font-size: 2rem; font-weight: bold; text-align: center;')
    with ui.card().style('min-width: 320px; max-width: 400px; width: 100%;').classes('fixed-center'):
        ui.label('Login').style('font-size: 2rem; font-weight: bold; text-align: center;')
        username = ui.input('Username').props('outlined').classes('mb-2 w-full')
        password = ui.input('Password', password=True).props('outlined').classes('mb-2 w-full')
        error = ui.label('').classes('text-red-500 text-xs mb-2 w-full')
        def do_login():
            if not username.value or not password.value:
                error.set_text('Username and password are required')
                return
            else:
                #Login with keycloak
                keycloak_url = f'https://keycloak.{base_dns}/realms/devtools/protocol/openid-connect/token'
                data = {            
                    'username': username.value,
                    'password': password.value,
                    'grant_type': 'password',
                    'client_id': 'dashboard',
                }
                if client_secret:
                    data['client_secret'] = client_secret
                headers = {'Content-Type': 'application/x-www-form-urlencoded'} 
                try:
                    verify = False if cert_type == 'selfsigned' else True
                    response = requests.post(keycloak_url, data=data, headers=headers, verify=verify)
                    if response.status_code == 200:
                        token = response.json().get('access_token')
                        if token:
                            ui.storage.set('token', token)
                            ui.navigate.to('/')
                        else:
                            error.set_text('Invalid username or password')
                    else:
                        error_json = response.json()
                        msg = error_json.get('error_description') or error_json.get('error') or response.text
                        error.set_text(f'Login failed: {msg}')
                except Exception as e:
                    error.set_text(f'Error: {str(e)}')

        ui.button('Login', color='blue', on_click=do_login).classes('w-full')

@ui.page('/dashboard')
def dashboard():
    set_background()     
    with ui.row().classes('w-full h-screen'):
        with ui.column().classes('w-1/4 bg-gray-200 p-4'):
            ui.label('Menú lateral')
            with ui.list().classes('w-full'):
                ui.item('Google').on('click', lambda: iframe.set_source('https://www.google.com'))
                ui.item('YouTube').on('click', lambda: iframe.set_source('https://www.youtube.com'))
                ui.item('Wikipedia').on('click', lambda: iframe.set_source('https://www.wikipedia.org'))

        with ui.column().classes('w-3/4 p-4'):
            iframe = ui.iframe('https://www.google.com').classes('w-full h-full')   

@ui.page('/')
def index():
    set_background()
    login()

if __name__ in {"__main__", "__mp_main__"}:
    base_dns = os.environ.get("BASE_DNS", "192.168.49.2.nip.io")
    cert_type = os.environ.get("CERT_TYPE", "selfsigned")
    client_secret = os.environ.get("CLIENT_SECRET")
    ui.run(
        port=8080,
        reload=True,
        title='Dev Tools Dashboard',
        favicon='https://nicegui.io/favicon.ico'
    )