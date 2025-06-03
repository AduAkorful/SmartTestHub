FROM node:18-alpine

# Install necessary dependencies
RUN apk add --no-cache bash git curl build-base libffi-dev openssl-dev python3 py3-pip

# Install chokidar-cli globally for file watching (if still needed)
RUN npm install -g chokidar-cli

# Install Slither (via pip)
RUN pip install slither-analyzer

WORKDIR /app

# Copy package.json and install Hardhat locally inside the container
COPY package.json package-lock.json* ./
RUN npm install

# Copy the rest of the project files
COPY entrypoint.sh /entrypoint.sh
COPY . .

# Fix line endings for entrypoint
RUN dos2unix /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
