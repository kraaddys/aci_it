# Лабораторная работа №3

## Тема

Автоматизация настройки сервера с помощью **Ansible**

## Цель работы

Настроить сервер Ubuntu через плейбуки Ansible:

1. Развернуть статический сайт с nginx.
2. Создать пользователя `deploy` с SSH-ключом и sudo без пароля.

---

## Ход выполнения

### 1. Подготовка виртуальной машины

Виртуальная машина запущена в **VirtualBox** с основанием на **Ubuntu 24.04 LTS**.

Установлены необходимые пакеты:

```bash
sudo apt update
sudo apt install -y ansible nginx
```

![image](https://i.imgur.com/6I99DEK.png)

![image](https://i.imgur.com/hK809B1.png)

---

### 2. Создание структуры Ansible-проекта

```bash
mkdir -p ~/ansible/{playbooks,files}
cd ~/ansible
```

![image](https://i.imgur.com/56srXCA.png)

Исходный скрипт файла `ansible.cfg`:

**ansible.cfg:**

```ini
[defaults]
inventory = inventory.ini
host_key_checking = False
interpreter_python = auto
```

![image](https://i.imgur.com/a7n0NIg.png)

Исходный скрипт файла `inventory.ini`:

**inventory.ini:**

```ini
[web]
localhost ansible_connection=local
```

![image](https://i.imgur.com/4ivliQP.png)

---

### 3. Плейбук 1 — nginx + развёртывание сайта

Созданы файлы:

* `files/mysite.conf` — минимальная конфигурация nginx;
* `files/site.tar.gz` — архив с сайтом (`index.html`).

Исходный скрипт файла `mysite.conf`:

```bash
cat > files/mysite.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;

    server_name _;

    root /var/www/mysite;
    index index.html;

    access_log /var/log/nginx/mysite_access.log;
    error_log  /var/log/nginx/mysite_error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
```

![image](https://i.imgur.com/UV9LPoP.png)

**Команда для упаковки сайта:**

```bash
mkdir -p /tmp/mysite && echo '<h1>Hello from Ansible</h1>' > /tmp/mysite/index.html
tar -C /tmp -czf files/site.tar.gz mysite
```

![image](https://i.imgur.com/0okt5OJ.png)

**playbooks/01_static_site.yml:**

Исходный скрипт файла `01_static_site.yml`:

```bash
cat > playbooks/01_static_site.yml << 'YAML'
---
- name: Static site via nginx + unarchive
  hosts: web
  become: true
  gather_facts: true

  vars:
    web_root: /var/www/mysite
    nginx_conf_src: mysite.conf
    nginx_conf_avail: /etc/nginx/sites-available/mysite.conf
    nginx_conf_enabled: /etc/nginx/sites-enabled/mysite.conf

  handlers:
    - name: reload nginx
      service:
        name: nginx
        state: reloaded

  tasks:
    # 1) Установить и запустить nginx
    - name: Ensure nginx is installed
      apt:
        name: nginx
        state: present
        update_cache: true

    - name: Ensure nginx started and enabled
      service:
        name: nginx
        state: started
        enabled: true

    # 2) Создать каталог /var/www/mysite
    - name: Create web root
      file:
        path: "{{ web_root }}"
        state: directory
        owner: www-data
        group: www-data
        mode: "0755"

    # 3) Распаковать files/site.tar.gz в /var/www/mysite
    - name: Unarchive site into web root
      unarchive:
        src: "../files/site.tar.gz"
        dest: "{{ web_root }}"
        owner: www-data
        group: www-data
        remote_src: false
        extra_opts: [--strip-components=1]  # извлечём содержимое без верхней папки
      notify: reload nginx

    # 4) Положить vhost и активировать (handler перезагрузит)
    - name: Place nginx vhost config
      copy:
        src: "../files/{{ nginx_conf_src }}"
        dest: "{{ nginx_conf_avail }}"
        owner: root
        group: root
        mode: "0644"
      notify: reload nginx

    - name: Enable site (symlink to sites-enabled)
      file:
        src: "{{ nginx_conf_avail }}"
        dest: "{{ nginx_conf_enabled }}"
        state: link
      notify: reload nginx

    - name: Remove default site (optional)
      file:
        path: /etc/nginx/sites-enabled/default
        state: absent
      notify: reload nginx

    - name: Test nginx config syntax
      command: nginx -t
      register: nginx_test
      changed_when: false

    - name: Show nginx test output
      debug:
        var: nginx_test.stderr_lines
YAML
```

![image](https://i.imgur.com/DKCQrgm.png)

Для запуска используем команду:

```bash
ansible-playbook playbooks/01_static_site.yml
```

![image](https://i.imgur.com/DlPPsVL.png)

![image](https://i.imgur.com/J7vq988.png)

**Результат:**

* nginx установлен и запущен;
* каталог `/var/www/mysite` создан;
* архив успешно распакован в web-директорию;
* конфигурация `mysite.conf` подключена в nginx;
* сайт доступен по адресу [http://127.0.0.1](http://127.0.0.1).

![image](https://i.imgur.com/RPzahJc.png)

---

### 4. Плейбук 2 — пользователь deploy + sudoers + SSH-ключ

Сначала создан ключ:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

Исходный скрипт файла `02_deploy_user.yml`:

```bash
cat > playbooks/02_deploy_user.yml << 'YAML'
---
- name: Deploy user + SSH key + sudoers drop-in
  hosts: web
  become: true
  gather_facts: true

  vars:
    deploy_user: deploy
    deploy_pubkey: "PASTE_YOUR_PUBLIC_KEY_HERE"   # <— замени на свой ключ
    sudo_group: sudo                               # в Ubuntu группа sudo

  tasks:
    # 1) Создать пользователя deploy и добавить в группу sudo
    - name: Ensure sudo group exists
      group:
        name: "{{ sudo_group }}"
        state: present

    - name: Create deploy user
      user:
        name: "{{ deploy_user }}"
        groups: "{{ sudo_group }}"
        append: true
        shell: /bin/bash
        create_home: true
        password: "!"     # без пароля, логин только по ключу
        state: present

    # 2) Прописать публичный ключ в authorized_keys
    - name: Create .ssh directory
      file:
        path: "/home/{{ deploy_user }}/.ssh"
        state: directory
        owner: "{{ deploy_user }}"
        group: "{{ deploy_user }}"
        mode: "0700"

    - name: Add authorized key
      authorized_key:
        user: "{{ deploy_user }}"
        key: "{{ deploy_pubkey }}"
        state: present
        manage_dir: false

    # 3) Создать sudoers drop-in
    - name: Write sudoers drop-in for deploy (with validation)
      copy:
        dest: "/etc/sudoers.d/{{ deploy_user }}"
        content: "{{ deploy_user }} ALL=(ALL) NOPASSWD:ALL\n"
        owner: root
        group: root
        mode: "0440"
        validate: "visudo -cf %s"

    # 4) Проверить синтаксис sudoers (доп. явная проверка)
    - name: Validate /etc/sudoers
      command: visudo -cf /etc/sudoers
      changed_when: false
YAML
```

![image](https://i.imgur.com/gdpQVMt.png)

Для запуска скрипта используется команда:

```bash
ansible-playbook playbooks/02_deploy_user.yml
```

![image](https://i.imgur.com/n123zLu.png)

![image](https://i.imgur.com/q56j0sq.png)

**Результат:**

* Пользователь `deploy` создан и добавлен в группу `sudo`.
* В `/home/deploy/.ssh/authorized_keys` добавлен публичный ключ.
* Создан `/etc/sudoers.d/deploy` с правилом `NOPASSWD:ALL`.

---

### 5. Проверка SSH-доступа

Для начала устанавливаем утилиту OpenSSH на виртуальную машину:

![image](https://i.imgur.com/FF6vcfV.png)

Затем выполняем проверку работоспособности SSH-сервера:

![image](https://i.imgur.com/8TjS22S.png)

Вход по ключу выполнен из-под обычного пользователя:

```bash
ssh -i ~/.ssh/id_ed25519 deploy@127.0.0.1
```

**Результат:** вход выполнен без пароля.

![image](https://i.imgur.com/q6iMN9c.png)

---

## Итоговые результаты

* nginx успешно развёрнут;
* сайт доступен локально;
* пользователь `deploy` настроен с SSH-доступом и sudo без пароля;
* оба плейбука работают корректно.

---

## Вывод

В данной лабораторной работе с помощью Ansible была автоматизирована настройка веб-сервера и создание пользователя для деплоя.
Все этапы выполены успешно, сервер готов к дальнейшей работе.
