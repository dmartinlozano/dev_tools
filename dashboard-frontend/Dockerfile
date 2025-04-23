FROM node:24.0.1-alpine3.21 AS build
WORKDIR /app
COPY src/package.json src/nuxt.config.ts ./
RUN rm -rf node_modules package-lock.json
RUN npm install
COPY src/ ./
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/.output/public /var/www/nuxt-spa
COPY ./nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]