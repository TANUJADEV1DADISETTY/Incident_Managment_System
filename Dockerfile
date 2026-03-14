FROM node:18-alpine

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm install

# Install curl for healthchecks
RUN apk add --no-cache curl

COPY . .

CMD [ "node", "src/index.js" ]
