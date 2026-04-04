FROM node:24-alpine

# Install system deps + 0g-compute-cli globally
RUN apk add --no-cache curl bash && \
    npm install -g @0glabs/0g-serving-broker

WORKDIR /app

# Install local SDK deps (ethers + broker for setup.mjs)
#COPY package.json ./
RUN npm install ethers @0glabs/0g-serving-broker

COPY setup.mjs ./

EXPOSE 3001

CMD ["node", "setup.mjs"]
