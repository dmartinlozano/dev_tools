FROM python:3.13.3-slim AS build
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONFAULTHANDLER 1
WORKDIR /installer
RUN apt-get update && apt-get install -y curl gnupg lsb-release
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
RUN pip install pipenv
COPY Pipfile .
RUN pipenv lock
RUN PIPENV_VENV_IN_PROJECT=1 pipenv install --deploy
COPY src/ ./src/
COPY tools/ ./tools/

FROM python:3.13.3-slim AS run
WORKDIR /installer
RUN apt-get update && apt-get install -y openjdk-17-jre-headless
COPY --from=build /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=build /usr/local/bin/helm /usr/local/bin/helm
COPY --from=build /root/.local /root/.local
COPY --from=build /installer/.venv /installer/.venv
COPY --from=build /installer/src /installer/src
COPY --from=build /installer/tools /installer/tools
RUN rm -rf /root/.kube/config && mkdir -p /root/.kube
ENV PATH="/installer/.venv/bin:$PATH"
ENV VIRTUAL_ENV="/installer/.venv"
ENV PYTHONPATH=/
ENV PYTHONDONTWRITEBYTECODE=1
EXPOSE 8080
CMD ["python", "src/main.py"]