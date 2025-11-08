## Лабораторная работа: Автоматизация развертывания многоконтейнерного приложения с Docker Compose с использованием Ansible

### Цель работы

Закрепить знания по Docker и Docker Compose путём автоматизации их установки и развертывания на виртуальной машине с помощью Ansible.
В ходе работы студент научился использовать инструменты конфигурационного управления (Ansible) совместно с контейнеризацией (Docker), создавая воспроизводимую инфраструктуру для деплоя веб-приложений.

---

### Ход выполнения

#### 1. Подготовка инфраструктуры

Для начала была проверена версия **Ansible**, чтобы быть уверенным в том, что он установлен. В консоли быто показано, что установлена самая актуальная версия.

Затем был создан каталог проекта `ansible-docker-lab` со структурой:

```
ansible-docker-lab/
├── ansible.cfg
├── inventory/hosts.ini
├── group_vars/docker_hosts.yml
├── install_docker.yml
├── deploy_compose.yml
└── files/docker-compose.yml
```

### 1.1. Подготовка структуры проекта:

```bash
mkdir -p ~/ansible-docker-lab/{inventory,group_vars,files}
cd ~/ansible-docker-lab
```

### 2. Настройка Ansible

**ansible.cfg**:

```ini
[defaults]
inventory = ./inventory/hosts.ini
host_key_checking = False
stdout_callback = yaml
timeout = 30
```

**inventory/hosts.ini**:

```ini
[docker_hosts]
localhost ansible_connection=local
```

**group_vars/docker_hosts.yml**:

```yaml
docker_apt_release: "jammy"
docker_packages:
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin

docker_users:
  - kraaddys
```

#### 3. Автоматизированная установка Docker

**Playbook `install_docker.yml`**:

```yaml
---
- name: Install Docker CE and Compose plugin on Ubuntu 22.04
  hosts: docker_hosts
  become: true
  gather_facts: true

  pre_tasks:
    - name: Ensure apt cache is up to date
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Install prerequisites
      apt:
        name: [ca-certificates, curl, gnupg, lsb-release]
        state: present

    - name: Create keyrings dir
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Add Docker GPG key
      get_url:
        url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.gpg
        mode: '0644'

    - name: Add Docker apt repository (stable)
      copy:
        dest: /etc/apt/sources.list.d/docker.list
        mode: '0644'
        content: |
          deb [arch={{ ansible_architecture | default('amd64') }} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu {{ docker_apt_release }} stable

    - name: apt update after adding Docker repo
      apt:
        update_cache: yes

  tasks:
    - name: Install Docker engine and plugins
      apt:
        name: "{{ docker_packages }}"
        state: present

    - name: Enable and start docker service
      systemd:
        name: docker
        state: started
        enabled: true

    - name: Add users to docker group
      user:
        name: "{{ item }}"
        groups: docker
        append: yes
      loop: "{{ docker_users }}"

    - name: Ensure /etc/docker exists
      file:
        path: /etc/docker
        state: directory
        mode: '0755'

    - name: Configure daemon.json
      copy:
        dest: /etc/docker/daemon.json
        mode: '0644'
        content: |
          {
            "exec-opts": ["native.cgroupdriver=systemd"],
            "log-driver": "json-file",
            "log-opts": { "max-size": "100m" },
            "storage-driver": "overlay2"
          }
      notify: Restart docker

  handlers:
    - name: Restart docker
      systemd:
        name: docker
        state: restarted
```

Что он выполняет:

* добавление репозитория Docker;
* установку `docker-ce`, `docker-ce-cli`, `containerd.io`;
* добавление пользователя `kraaddys` в группу docker;
* запуск сервиса Docker.

Перед запуском плейбука проводится проверка соединения соединения Ansible с целевыми хостами. Для этого используется команда:

```bash
ansible -m ping docker_hosts
```

![image](https://i.imgur.com/5ye3WoK.png)

После чего запуска плейбука используется команда:

```bash
ansible-playbook install_docker.yml
```

![image](https://i.imgur.com/xRZKe0n.png)

![image](https://i.imgur.com/1WzTsmn.png)

Результат при успешном выполнении:

```
PLAY RECAP ************************************************************
localhost : ok=13  changed=4  unreachable=0  failed=0  skipped=0
```

---

#### 4. Создание Docker Compose для WordPress + MySQL

**docker-compose.yml**:

```yaml
version: "3.9"
services:
  db:
    image: mysql:8.0
    container_name: wp-db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppass
      MYSQL_ROOT_PASSWORD: rootpass
    volumes:
      - db_data:/var/lib/mysql
    networks: [wpnet]

  wordpress:
    image: wordpress:latest
    container_name: wp-app
    depends_on: [db]
    restart: unless-stopped
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppass
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - wp_data:/var/www/html
    networks: [wpnet]

volumes:
  db_data:
  wp_data:

networks:
  wpnet:
    driver: bridge
```

---

#### 5. Деплой WordPress через Ansible

**deploy_compose.yml**:

```yaml
---
- name: Deploy WordPress stack with Docker Compose
  hosts: docker_hosts
  become: true
  vars:
    deploy_dir: /opt/wordpress-stack
    compose_filename: docker-compose.yml

  tasks:
    - name: Ensure deploy directory exists
      file:
        path: "{{ deploy_dir }}"
        state: directory
        owner: "{{ ansible_user | default('root') }}"
        group: "{{ ansible_user | default('root') }}"
        mode: "0755"

    - name: Copy docker-compose.yml
      copy:
        src: files/{{ compose_filename }}
        dest: "{{ deploy_dir }}/{{ compose_filename }}"
        mode: "0644"

    - name: Pull images
      command: docker compose pull
      args: { chdir: "{{ deploy_dir }}" }

    - name: Start stack
      command: docker compose up -d
      args: { chdir: "{{ deploy_dir }}" }

    - name: Show running containers
      command: docker ps --format "table {{'{{'}}.Names{{'}}'}}\t{{'{{'}}.Image{{'}}'}}\t{{'{{'}}.Status{{'}}'}}\t{{'{{'}}.Ports{{'}}'}}"
      register: ps_out
      changed_when: false

    - name: Print docker ps
      debug:
        msg: "{{ ps_out.stdout_lines }}"
```

---

#### 6. Проверка работы

```bash
curl -I http://localhost/
```

Результат:

```
HTTP/1.1 302 Found
Server: Apache/2.4.65 (Debian)
X-Powered-By: PHP/8.3.27
Location: http://localhost/wp-admin/install.php
```

![image](https://i.imgur.com/PfyuP4o.png)

Далее вручную при помощи встроенного браузера в ВМ запускается `localhost` с базовой страницы WordPress, далее просто была произведена настройка сервиса.

![image](https://i.imgur.com/f24pLkd.png)

![image](https://i.imgur.com/UKUSeKP.png)

![image](https://i.imgur.com/ZB9KhKf.png)

![image](https://i.imgur.com/b395txP.png)

---

### Вывод

В ходе лабораторной работы были:

* автоматизированы установка Docker и Docker Compose с помощью Ansible;
* развёрнут стек **WordPress + MySQL**;
* подтверждена работоспособность веб-приложения.

В итоге достигнута цель интеграции **Ansible** и **Docker** для создания reproducible-инфраструктуры.

