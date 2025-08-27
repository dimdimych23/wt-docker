#!/bin/sh
set -e

# 1) Составить список переменных из шаблона (только ${VAR}, а не $host)
VARS_MAIN="$(grep -o '\${[A-Za-z0-9_]\+}' /etc/nginx/nginx.conf.template | sort -u | tr '\n' ' ')"
# 2) Прогнать envsubst только по этим переменным
envsubst "$VARS_MAIN" < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
# 3) Каталог фич и очистка
mkdir -p /etc/nginx/conf.d/features
rm -f /etc/nginx/conf.d/features/*.conf

# 4) VCLASS (media+recorder в одном файле) по флагу
if [ "${NGINX_ENABLE__VCLASS:-false}" = "true" ]; then
  VARS_VCLASS="$(grep -o '\${[A-Za-z0-9_]\+}' /etc/nginx/templates/features/vclass.feature.template | sort -u | tr '\n' ' ')"
  envsubst "$VARS_VCLASS" < /etc/nginx/templates/features/vclass.feature.template > /etc/nginx/conf.d/features/vclass.conf
fi

# 4) Проверка конфига (провалит запуск, если что-то не так)
nginx -t