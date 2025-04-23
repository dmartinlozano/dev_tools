FROM python:3.13.3-slim AS build
WORKDIR /app/src
RUN apt-get update && apt-get install -y curl gnupg lsb-release
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
RUN pip install pipenv
COPY Pipfile ../
RUN pipenv install --deploy --ignore-pipfile
COPY src/ .

FROM python:3.13.3-slim AS run
WORKDIR /app/src
RUN apt-get update && apt-get install -y openjdk-17-jre-headless
RUN pip install pipenv
COPY --from=build /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=build /usr/local/bin/helm /usr/local/bin/helm
COPY --from=build /root/.local /root/.local
COPY --from=build /app/Pipfile /app/Pipfile
COPY --from=build /app/src /app/src
RUN rm -rf /root/.kube/config && mkdir -p /root/.kube
ENV PATH=/root/.local/bin:$PATH
EXPOSE 8080
CMD ["pipenv", "run", "python", "main.py"]