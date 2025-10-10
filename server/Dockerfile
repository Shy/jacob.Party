FROM swift:6.2

WORKDIR /app

COPY . .

RUN swift build -c release

EXPOSE 8080

CMD [".build/release/App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
