FROM python:3.10-slim

WORKDIR /opt
RUN apt-get update && apt-get install -y --no-install-recommends git gcc && \
    git clone https://github.com/0xSpace-dev/starknet-devnet.git && \
    cd starknet-devnet && pip install .

EXPOSE 5050

ENTRYPOINT ["starknet-devnet"]
