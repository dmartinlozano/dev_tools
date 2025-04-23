FROM python:3.13.3-slim
WORKDIR /app/src
RUN pip install pipenv
COPY Pipfile ../
RUN pipenv install --deploy --ignore-pipfile
COPY src/ .
EXPOSE 8000
CMD ["pipenv", "run", "python", "main.py"]