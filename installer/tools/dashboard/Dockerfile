FROM python:3.13.3-slim AS build
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONFAULTHANDLER 1
WORKDIR /app
RUN pip install pipenv
COPY Pipfile .
RUN pipenv lock
RUN PIPENV_VENV_IN_PROJECT=1 pipenv install --deploy
RUN rm Pipfile Pipfile.lock
COPY src/ ./src/

FROM python:3.13.3-slim AS run
WORKDIR /app
COPY --from=build /app/src /app/src
COPY --from=build /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
ENV VIRTUAL_ENV="/app/.venv"
ENV PYTHONPATH=/app
ENV PYTHONDONTWRITEBYTECODE=1
EXPOSE 443
CMD ["python", "src/main.py"]