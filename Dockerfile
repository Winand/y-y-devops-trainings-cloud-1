FROM golang:1.21 as builder

COPY catgpt /catgpt
WORKDIR /catgpt
# RUN go mod download
RUN go mod tidy
RUN CGO_ENABLED=0 go build -o /catgpt/bin/catgpt

# base-debian12 image also contains libc, libssl
# https://github.com/GoogleContainerTools/distroless/blob/main/base/README.md
FROM gcr.io/distroless/static-debian12:latest-amd64
COPY --from=builder /catgpt/bin/catgpt /usr/bin/catgpt

EXPOSE 8080 9090
ENTRYPOINT [ "catgpt" ]
