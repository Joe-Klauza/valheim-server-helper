FROM steamcmd/steamcmd:latest

RUN apt-get update && \
	apt-get install -y libsdl2-2.0-0:i386 git gcc g++ make curl libssl-dev libyaml-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /home/valheim
ENV HOME="/home/valheim"
ENV PATH=$HOME/.rbenv/bin:$PATH

COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

ENTRYPOINT  ["/home/valheim/entrypoint.sh"]
