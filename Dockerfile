FROM node:22.22.0-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --cache .npm --prefer-offline

COPY . .
RUN npm run build

FROM nginx:1.27-alpine AS runtime

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist/olympic-games-starter/browser/ /app/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]