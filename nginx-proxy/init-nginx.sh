#!/bin/sh
set -e

# 1) Главный конфиг из шаблона
envsubst < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# 2) Каталог фич и очистка
mkdir -p /etc/nginx/conf.d/features
rm -f /etc/nginx/conf.d/features/*.conf

# 3) VCLASS (media+recorder в одном файле) по флагу
if [ "${NGINX_ENABLE_VCLASS:-false}" = "true" ]; then
  envsubst < /etc/nginx/vclass.feature.template \
    > /etc/nginx/conf.d/features/vclass.conf
fi

# 4) Проверка конфига (провалит запуск, если что-то не так)
nginx -t