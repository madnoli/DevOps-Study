# Small, official base. The image's entrypoint already renders
# /etc/nginx/templates/*.template into /etc/nginx/conf.d/ at start-up,
# so no extra script is needed.
FROM nginx:1.27-alpine

# Fallbacks for running outside Kubernetes (plain `docker run`).
# In the cluster the Deployment overrides these via the downward API.
ENV POD_NAME=local \
    POD_IP=unknown \
    NODE_NAME=docker

COPY default.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 80
