#!/bin/bash
set -e

# first check if network and DB exist
docker network create odin-prod-net 2>/dev/null || true
if [ ! "$(docker ps -q -f name=odin-prod-db)" ]; then
    docker run -d --name odin-prod-db --network odin-prod-net -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=productionpassword postgres:14
    sleep 5
fi

# pull the latest image pushed by Jenkins and start it
docker pull hassanjamali/odin-app:latest
docker run -d \
  --name odin-prod-app \
  --network odin-prod-net \
  -p 3000:3000 \
  --env-file /home/ubuntu/.env \
  -e RAILS_ENV=production \
  -e SECRET_KEY_BASE=production_secret_key_base_32_characters_long_val \
  -e DATABASE_URL=postgresql://postgres:productionpassword@odin-prod-db:5432/odin_production \
  hassanjamali/odin-app:latest \
  sh -c "bundle exec rails db:prepare && bin/rails server -b 0.0.0.0"