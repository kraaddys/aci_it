## Лабораторная работа: Расширенный пайплайн в GitLab CI для Laravel

### Цель работы

Ознакомиться с практической настройкой CI/CD-конвейера на базе GitLab Community Edition для Laravel-приложения:

* развернуть GitLab CE в Docker;
* настроить GitLab Runner с executor’ом Docker;
* создать проект с Laravel-приложением;
* настроить пайплайн с тестированием и сборкой Docker-образа;
* включить GitLab Container Registry и опубликовать в него собранный образ.

---

## 2. Оборудование и ПО

* Хост-машина: Windows + VirtualBox
* Гостевая ОС: Ubuntu 24.04 Server (VM `myVirtualMachine`)
* Docker + Docker Compose
* GitLab CE (контейнер `gitlab/gitlab-ce:latest`)
* GitLab Runner (`gitlab-runner` из репозитория GitLab)
* PHP 8.2, Laravel 11 (шаблонный проект с GitHub)
* MySQL 8.0 (как service в GitLab CI)
* Docker-registry (встроенный в GitLab, порт 5050)

---

## 3. Задания лабораторной работы

1. Развернуть GitLab CE и настроить доступ.
2. Установить и зарегистрировать GitLab Runner.
3. Создать проект с Laravel-приложением и настроить стадии тестирования.
4. Реализовать стадию сборки Docker-образа приложения.
5. Включить GitLab Container Registry и убедиться, что собранный образ туда загружается.

В отчёте ниже каждый шаг будет привязан к этим пунктам.

---

## 4. Ход выполнения работы

### 4.1. Развёртывание GitLab CE в Docker

На виртуальной машине был запущен контейнер GitLab CE:

```bash
docker run -d \
  --hostname 192.168.56.101 \
  -p 80:80 \
  -p 443:443 \
  -p 8022:22 \
  -p 5050:5050 \
  --name gitlab \
  -e GITLAB_OMNIBUS_CONFIG="external_url 'http://192.168.56.101'; gitlab_rails['gitlab_shell_ssh_port']=8022;" \
  -v gitlab-data:/var/opt/gitlab \
  -v ~/gitlab-config:/etc/gitlab \
  gitlab/gitlab-ce:latest
```

* `external_url` — главный HTTP-адрес GitLab.
* Порт `8022` проброшен под SSH-доступ к репозиториям.
* Порт `5050` — будущий порт для Container Registry.

После запуска по адресу `http://192.168.56.101/` открылся веб-интерфейс GitLab.
Первичный пароль для пользователя `root` был просмотрен командой:

![image](https://i.imgur.com/dDVyLru.png)

```bash
docker exec -it gitlab cat /etc/gitlab/initial_root_password
```

![image](https://i.imgur.com/tlPFIOv.png)

![image](https://i.imgur.com/C9MMYjN.png)

---

### 4.2. Включение GitLab Container Registry

Внутри тома `~/gitlab-config` был отредактирован файл `gitlab.rb`:

```bash
sudo nano ~/gitlab-config/gitlab.rb
```

Раскомментирован и изменён блок настроек Registry:

```ruby
## Container Registry settings
registry_external_url 'http://192.168.56.101:5050'

gitlab_rails['registry_enabled'] = true
gitlab_rails['registry_host'] = '192.168.56.101'
gitlab_rails['registry_port'] = '5050'
gitlab_rails['registry_path'] = "/var/opt/gitlab/gitlab-rails/shared/registry"
```

После изменения настроек контейнер GitLab был перезапущен:

```bash
docker restart gitlab
```

Проверка работы Registry:

```bash
curl http://192.168.56.101:5050/v2/
```

Ответ вида:

```json
{"errors":[{"code":"UNAUTHORIZED","message":"authentication required","detail":null}]}
```

говорит о том, что **registry запущен и отвечает**, но требует авторизацию (это нормальное поведение).

*(сюда скрин с ответом /v2/ в браузере или через curl)*

---

### 4.3. Настройка Docker-демона на хосте (для работы с registry)

Чтобы docker-клиент на виртуалке нормально работал с нашим HTTP-registry без TLS, в файл `/etc/docker/daemon.json` добавлены настройки:

```json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "insecure-registries": ["192.168.56.101:5050"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m" },
  "storage-driver": "overlay2"
}
```

Перезапуск Docker:

```bash
sudo systemctl restart docker
```

Проверка:

```bash
docker info | grep -A3 "Insecure Registries"
```

В списке появилась строка `192.168.56.101:5050`.

*(скрин вывода docker info с Insecure Registries)*

---

### 4.4. Установка GitLab Runner и регистрация

Установка runner’а:

```bash
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get install -y gitlab-runner
```

![image](https://i.imgur.com/aYLcvt6.png)

Регистрация instance runner’а выполнялась по токену из **Admin area → CI/CD → Runners → Create instance runner**.

![image](https://i.imgur.com/gh8i2RG.png)

![image](https://i.imgur.com/TPDfqsi.png)

Пример команды регистрации:

```bash
sudo gitlab-runner register \
  --url "http://192.168.56.101" \
  --token "my_token" \
  --executor "docker" \
  --docker-image "php:8.2-cli" \
  --description "laravel-runner-2"
```

![image](https://i.imgur.com/4AEFHeH.png)

![image](https://i.imgur.com/zeI59uI.png)

После регистрации runner появился в интерфейсе GitLab в разделе **Admin → CI/CD → Runners** как Online.

![image](https://i.imgur.com/Yw0LAlM.png)

---

### 4.5. Создание проекта `laravel-app` и загрузка исходников

1. В веб-интерфейсе GitLab создан пустой проект `laravel-app` (space: `root/laravel-app`).

![image](https://i.imgur.com/MA7tPNf.png)

2. Репозиторий был клонирован на виртуальную машину:

   ```bash
   git clone http://192.168.56.101/root/laravel-app.git
   cd laravel-app
   ```

3. В соседнюю директорию был склонирован официальный шаблон Laravel:

   ```bash
   git clone https://github.com/laravel/laravel.git
   ```

![image](https://i.imgur.com/7Xq3tqc.png)

![image](https://i.imgur.com/TavDWiU.png)

4. Содержимое шаблона было скопировано в репозиторий GitLab:

   ```bash
   cp -r ./laravel/* ./laravel-app/
   cd laravel-app
   ```

5. Изменения закоммичены и запушены, но перед этим регистрируем пользователя:

![image](https://i.imgur.com/Mndwrbp.png)

   ```bash
   git add .
   git commit -m "Add Laravel app with CI/CD config"
   git push origin main
   ```

![image](https://i.imgur.com/xWch78R.png)

![image](https://i.imgur.com/eFyM7G2.png)

---

### 4.6. Подготовка окружения Laravel для тестирования

Создан файл `.env.testing` с настройками для тестовой базы данных, использующей сервис `mysql` в CI:

```env
APP_NAME=Laravel
APP_ENV=testing
APP_KEY=
APP_DEBUG=true
APP_URL=http://localhost
APP_LOCALE=en
APP_FALLBACK_LOCALE=en
APP_FAKER_LOCALE=en_US
APP_MAINTENANCE_DRIVER=file
# APP_MAINTENANCE_STORE=database
PHP_CLI_SERVER_WORKERS=4
BCRYPT_ROUNDS=12
LOG_CHANNEL=stack
LOG_STACK=single
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=laravel_test
DB_USERNAME=root
DB_PASSWORD=root

SESSION_DRIVER=database
SESSION_LIFETIME=120
SESSION_ENCRYPT=false
SESSION_PATH=/
SESSION_DOMAIN=null

BROADCAST_CONNECTION=log
FILESYSTEM_DISK=local
QUEUE_CONNECTION=database
CACHE_STORE=database

# CACHE_PREFIX=
MEMCACHED_HOST=127.0.0.1

REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=log
MAIL_SCHEME=null
MAIL_HOST=127.0.0.1
MAIL_PORT=2525
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="${APP_NAME}"
```

Также в `tests/Feature/ExampleTest.php` оставлен стандартный тест Laravel, проверяющий, что главная страница возвращает код 200.

---

### 4.7. Dockerfile для Laravel-приложения

В корне проекта создан `Dockerfile`:

```dockerfile

FROM php:8.2-apache

# Устанавливаем зависимости
RUN apt-get update && apt-get install -y \
    git \
    zip unzip \
    libpng-dev libonig-dev libxml2-dev \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath
    
# Устанавливаем Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Копируем код приложения
COPY . /var/www/html
RUN composer install --no-scripts --no-interaction
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
RUN chmod -R 775 /var/www/html/storage

RUN a2enmod rewrite
EXPOSE 80

CMD ["apache2-foreground"]
```

Этот Dockerfile использовался как в ручной сборке, так и в CI.

---

### 4.8. Настройка пайплайна GitLab CI (.gitlab-ci.yml)

Файл `.gitlab-ci.yml`:

```yaml
stages:
  - test
  - build

variables:
  MYSQL_DATABASE: laravel_test
  MYSQL_ROOT_PASSWORD: root
  DB_HOST: mysql

test:
  stage: test
  image: php:8.2-cli
  services:
    - mysql:8.0
  before_script:
    - apt-get update -yqq
    - apt-get install -yqq libpng-dev libonig-dev libxml2-dev libzip-dev unzip git
    - docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath
    - curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    - composer install --no-scripts --no-interaction
    - cp .env.testing .env
    - php artisan key:generate
    - php artisan migrate --seed
    - cp .env .env.testing
    - php artisan config:clear
  script:
    - vendor/bin/phpunit
  after_script:
    - rm -f .env
build:
  stage: build
  image: docker:25.0.3
  services:
    - docker:25.0.3-dind
  variables:
    DOCKER_HOST: tcp://docker:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    - docker info
    - docker build -t laravel-ci-build .
```

![image](https://i.imgur.com/nUmZDIj.png)

В такой конфигурации:

* `test` — полностью проверяет Laravel-приложение (запуск миграций и PHPUnit-тестов).
* `build` — внутри Docker-runner’а собирает образ `laravel-ci-build` по нашему Dockerfile.

> Отдельно от CI был выполнен ручной push образа в registry (см. шаг 4.10).

---

### 4.9. Проверка работоспособности тестов

При push’е в ветку `main`:

1. GitLab запускает пайплайн.
2. Job `test`:

    * разворачивает MySQL 8.0 как сервис;
    * ставит зависимости через Composer;
    * выполняет `php artisan migrate --seed`;
    * запускает `vendor/bin/phpunit`.

Логи показывают успешное прохождение 2 тестов, без ошибок `MissingAppKey` и других:

```text
OK (2 tests, 2 assertions)
Job succeeded
```

---

### 4.10. Сборка и загрузка Docker-образа в GitLab Container Registry

После того как registry был настроен и Docker помечен как `insecure-registry`, были выполнены команды **ручной сборки и push’а** образа (это важно для демонстрации работы Registry):

```bash
cd ~/laravel-app

# Сборка образа с тегом в реестре GitLab
docker build -t 192.168.56.101:5050/root/laravel-app:manual .

# Логин в реестр под пользователем root
docker login 192.168.56.101:5050
# (вводился пароль пользователя root GitLab)

# Отправка образа в реестр
docker push 192.168.56.101:5050/root/laravel-app:manual
```

В процессе push все слои были успешно загружены, в конце сообщение:

После этого в веб-интерфейсе GitLab, в проекте `laravel-app`, появился раздел:

**Deploy → Container Registry**

и внутри — репозиторий `192.168.56.101:5050/root/laravel-app` с тегом `manual`.

*(скрин Container Registry со списком тегов)*

Таким образом, условие задания:

> «Проверьте Packages & Registries → Container Registry — образ должен быть доступен.»

— выполнено.

![image](https://i.imgur.com/gksawnI.png)

![image](https://i.imgur.com/81yeZuR.png)

---

### 4.11. Итоговая проверка пайплайна и Registry

1. В разделе **CI/CD → Pipelines** виден пайплайн с двумя стадиями:
   `test` → `build` со статусом **Passed**.
2. В разделе **Deploy → Container Registry** отображается собранный и запушенный образ `root/laravel-app:manual`.
3. При желании образ можно забрать с другой машины:

   ```bash
   docker login 192.168.56.101:5050
   docker pull 192.168.56.101:5050/root/laravel-app:manual
   ```

---

## 6. Вывод

В ходе лабораторной работы было:

* Развёрнут GitLab Community Edition в Docker на виртуальной машине Ubuntu.
* Включён и настроен встроенный GitLab Container Registry (порт 5050).
* Установлен и зарегистрирован GitLab Runner с Docker-executor’ом.
* Создан проект `laravel-app`, загружен шаблонный Laravel-проект.
* Настроен файл `.gitlab-ci.yml` c двумя стадиями:
  **test** (Composer + миграции + PHPUnit) и **build** (сборка Docker-образа).
* Настроена работа Docker с нестандартным HTTP-registry через `insecure-registries`.
* Собран Docker-образ Laravel-приложения и загружен в GitLab Container Registry.
* Успешно проверена работоспособность пайплайна и регистра.

Поставленная цель — получить практический опыт настройки CI/CD-конвейера для Laravel-приложения на базе GitLab CE и Docker — достигнута.
