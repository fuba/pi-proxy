FROM perl:5.36

RUN apt-get update && apt-get install -y \
    libssl-dev \
    zlib1g-dev \
    libxml2-dev \
    libexpat1-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cpanm --notest Carton

COPY . /app
WORKDIR /app
RUN carton install

EXPOSE 5000

CMD ["carton", "exec", "plackup", "-p", "5000", "-a", "app.psgi"]
