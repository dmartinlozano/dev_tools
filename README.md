# configure minikube for testing

To configure minikube:
```
chmod +x minikube-setup-macos.sh
./minikube-setup-macos.sh
```

Previous install:
execute `minikube ip` and add
```
192.168.49.2      dashboard.192.168.49.2.nip.io keycloak.192.168.49.2.nip.io
```
to `/etc/hosts` with root privileges and run
```
minikube tunnel
```

If you need it:
```
minikube addons enable dashboard
```

And later, install:
```
chmod +x install.sh
./install.sh
```

# configure k8s 

```
chmod +x install.sh
./install.sh

```

# tools
- email: Mail-0
- git: Forgejo
- agile: taiga
- cd-ci: jenkins
- doc: wikijs, bootsnote ?
- storing artifacts: nexus
- quality: sonarQube & testlink
- communications: mattermost
- storing: minio
- office: collabora (con nextcloud configurado como oidc ? )
- meet: jitsi meet


# Paths de vaults
- transit/decrypt/vault-unseal-key  Keys para sellado
- transit/encrypt/vault-unseal-key  Keys para sellado
- transit/keys/vault-unseal-key     Keys para sellado
- secret/dev-tools/postgresql/admin        'password' del usuario postgres
- secret/dev-tools/postgresql/keycloak     'username','password' para acceder a bbdd
- secret/dev-tools/keycloak/admin          'username','password'
- secret/dev-tools/keycloak/keystore        '', 'password' 

## ¿cuando es secret/data/dev-tools ... ?
- ¿secret/data/ se usa en un policy hcl? Sí
- ¿secret/data/ se usa en vault kv put? No
- ¿secret/data/ se usa en values.yaml de keycloak? Sí

# TODO
- keycloak en modo producción


# RBAC
Para definir un sistema de control de acceso **RBAC (Role-Based Access Control)** en **Keycloak** con usuarios, permisos CRUD y aplicaciones como **Jenkins**, **Forgejo**, **Taiga**, y **SonarQube**, necesitas configurar varios elementos en Keycloak. Esto incluye la creación de **roles**, la asignación de esos roles a los usuarios, y la configuración de **políticas de autorización** para que las aplicaciones gestionen los permisos adecuados según los roles.

A continuación, te guiaré paso a paso sobre cómo hacerlo en la consola de **Keycloak**.

---

### **1. Crear Roles Globales**

Primero, necesitarás definir los **roles globales** que se asignarán a los usuarios. Estos roles son roles generales que describen el tipo de acceso que un usuario tendrá en todo el sistema.

#### Pasos:

1. Entra en la consola de **Keycloak**.
2. Ve a tu **realm** (puedes usar el **realm** predeterminado o crear uno nuevo).
3. Navega a la sección **Roles** en el menú izquierdo.
4. Haz clic en **Add Role** para crear roles globales, por ejemplo:

   * **admin**: Acceso total a todas las aplicaciones y configuraciones.
   * **developer**: Acceso para desarrollar y administrar aplicaciones (CRUD en recursos).
   * **viewer**: Acceso solo de lectura.

#### Ejemplo de roles globales:

* `admin`
* `developer`
* `viewer`

---

### **2. Crear Roles Específicos por Aplicación**

En la misma sección de **Roles**, puedes crear roles específicos para cada aplicación, lo que te permitirá controlar los permisos de cada usuario en función de la aplicación que esté utilizando (Jenkins, Forgejo, Taiga, SonarQube, etc.).

#### Pasos:

1. Ve a **Roles** y selecciona el **cliente** (si aún no lo tienes, debes crear un cliente en la sección de **Clientes** para cada aplicación).
2. Dentro del cliente correspondiente, crea roles específicos. Por ejemplo:

   * **Jenkins**:

     * `jenkins_admin`
     * `jenkins_user`
     * `jenkins_viewer`
   * **Forgejo**:

     * `forgejo_admin`
     * `forgejo_user`
     * `forgejo_viewer`
   * **Taiga**:

     * `taiga_admin`
     * `taiga_user`
     * `taiga_viewer`
   * **SonarQube**:

     * `sonarqube_admin`
     * `sonarqube_user`
     * `sonarqube_viewer`

#### Ejemplo de roles por aplicación:

* **Jenkins**: `jenkins_admin`, `jenkins_user`, `jenkins_viewer`
* **Forgejo**: `forgejo_admin`, `forgejo_user`, `forgejo_viewer`
* **Taiga**: `taiga_admin`, `taiga_user`, `taiga_viewer`
* **SonarQube**: `sonarqube_admin`, `sonarqube_user`, `sonarqube_viewer`

---

### **3. Asignar Roles a los Usuarios**

Una vez que los roles estén definidos, puedes asignarlos a los usuarios. Puedes hacerlo de forma manual, o de manera automática, si tu integración es más avanzada (usando eventos o API).

#### Pasos:

1. Ve a la sección **Users** en el menú izquierdo de la consola de Keycloak.
2. Selecciona un **usuario**.
3. En el perfil del usuario, ve a la pestaña **Role Mappings**.
4. Asigna los roles que corresponden al usuario:

   * Roles **globales**: `admin`, `developer`, `viewer`.
   * Roles **específicos de cliente**: `jenkins_admin`, `forgejo_user`, `taiga_viewer`, etc.

#### Ejemplo de asignación de roles:

* Usuario `johndoe`:

  * Roles globales: `developer`
  * Roles específicos de cliente: `jenkins_user`, `forgejo_viewer`, `taiga_user`

---

### **4. Configuración de Políticas de Autorización (Opcional)**

Si quieres tener más control sobre los permisos (CRUD) dentro de Keycloak para cada recurso o aplicación, puedes configurar políticas de autorización que utilicen estos roles.

#### Pasos para configurar políticas de autorización:

1. Entra en la sección **Clients**.
2. Selecciona un **cliente** (por ejemplo, **Jenkins**).
3. Ve a la pestaña **Authorization**.
4. Activa **Authorization Enabled** para habilitar la autorización en Keycloak.
5. En la sección **Resources**, define los recursos para los que quieras aplicar políticas. Ejemplo: `jenkins_job`, `forgejo_repo`, etc.
6. En la sección **Policies**, puedes crear **políticas** que se basen en los roles. Ejemplo:

   * **Permiso de lectura (ver trabajos en Jenkins)**: Asocia el rol `jenkins_viewer` con este permiso.
   * **Permiso de actualización (editar trabajos en Jenkins)**: Asocia el rol `jenkins_user` con este permiso.
   * **Permiso de eliminación (eliminar trabajos en Jenkins)**: Asocia el rol `jenkins_admin` con este permiso.

#### Ejemplo de política:

* **Lectura de Jenkins (ver trabajos)**:

  * **Política**: Permite a los usuarios con el rol `jenkins_viewer` acceder a los trabajos.
* **Creación de Jenkins (crear trabajos)**:

  * **Política**: Permite a los usuarios con el rol `jenkins_user` crear trabajos en Jenkins.
* **Administración de Jenkins (eliminar trabajos)**:

  * **Política**: Permite a los usuarios con el rol `jenkins_admin` eliminar trabajos.

---

### **5. Integración con Aplicaciones Externas (Jenkins, Forgejo, Taiga, SonarQube)**

Para que Keycloak gestione la autenticación y autorización de las aplicaciones externas como **Jenkins**, **Forgejo**, **Taiga** y **SonarQube**, necesitarás configurar cada aplicación para usar **Keycloak** como proveedor de identidad mediante **OAuth2** o **OpenID Connect**.

#### **Jenkins**:

* Instala el plugin **Keycloak Authentication** en Jenkins.
* Configura Jenkins para usar **Keycloak** como proveedor de autenticación.
* Usa el rol `jenkins_admin`, `jenkins_user`, etc., para controlar el acceso dentro de Jenkins.

#### **Forgejo**:

* Configura **Forgejo** para usar Keycloak mediante el protocolo **OIDC**.
* Asigna roles como `forgejo_admin`, `forgejo_user`, etc., para gestionar permisos de acceso.

#### **Taiga**:

* Taiga también puede integrarse con **Keycloak** a través de **OIDC** o **OAuth2**.
* Los roles `taiga_admin`, `taiga_user`, etc., controlarán el acceso a proyectos y tareas.

#### **SonarQube**:

* SonarQube permite integrarse con Keycloak mediante **LDAP** o **OIDC**.
* Configura los roles en Keycloak (como `sonarqube_admin`, `sonarqube_user`) y sincronízalos con SonarQube para definir el acceso a proyectos y métricas de código.

---

### **6. Sincronización de Roles y Permisos (Avanzado)**

Si prefieres que los roles y permisos se sincronicen dinámicamente entre Keycloak y tus aplicaciones, puedes:

1. **Usar eventos de Keycloak**: Cuando un usuario es creado o se le asignan roles, puedes hacer que Keycloak envíe una notificación a tus aplicaciones para que ajusten los permisos.
2. **API de Keycloak**: Utiliza las APIs de Keycloak para crear, asignar y modificar roles automáticamente desde tus sistemas internos.
3. **Políticas avanzadas de autorización**: Usa las políticas de Keycloak para controlar el acceso a recursos más complejos, usando roles y atributos de usuarios.

---

### **Resumen de la Configuración en Keycloak:**

1. **Crear Roles**: Define roles globales y específicos para cada aplicación (Jenkins, Forgejo, Taiga, SonarQube).
2. **Asignar Roles a Usuarios**: Asocia los roles adecuados a los usuarios (por ejemplo, `developer`, `jenkins_user`).
3. **Configurar Políticas de Autorización**: Usa las políticas de autorización de Keycloak para definir permisos de acceso basados en roles (CRUD).
4. **Integrar con Aplicaciones**: Configura cada aplicación para usar Keycloak como proveedor de autenticación y autorización.

Si necesitas ejemplos de configuración o ayuda con la integración de una de las aplicaciones mencionadas, no dudes en pedírmelo. ¡Estoy aquí para ayudarte!

# run back and front in dev

`brew install pipenv``

```
deactivate
pipenv --rm
cd installer
pipenv shell
pipenv install
export PYTHONPATH=$PWD/../common
pipenv run python src/main.py --reload
```
```
chmod +x ./installer/tools/dashboard/k8s/replace-vars.sh
./installer/tools/dashboard/k8s/replace-vars.sh
skaffold dev --cache-artifacts=false
```

# dev tips
minikube delete && ./minikube-setup-macos.sh && minikube tunnel
./install.sh