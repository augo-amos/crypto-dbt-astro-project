from datetime import datetime, timedelta
from airflow import DAG
# from airflow.operators.bash import BashOperator
from airflow.providers.standard.operators.bash import BashOperator

default_args = {
    'depends_on_past': False,
    'start_date': datetime(2024, 5, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'crypto_dbt_pipeline',
    default_args=default_args,
    description='Run dbt transformations for crypto data',
    schedule_interval='@daily',
    catchup=False,
    tags=['crypto', 'dbt'],
) as dag:
    
    dbt_project_path = '/workspaces/codespaces-blank/astro_dbt/dags/crypto_dbt'
    
    # Task 1: Run dbt seeds
    dbt_seed = BashOperator(
        task_id='dbt_seed',
        bash_command=f'cd {dbt_project_path} && dbt seed',
    )
    
    # Task 2: Run dbt models
    dbt_run = BashOperator(
        task_id='dbt_run',
        bash_command=f'cd {dbt_project_path} && dbt run',
    )
    
    # Task 3: Run dbt tests
    dbt_test = BashOperator(
        task_id='dbt_test',
        bash_command=f'cd {dbt_project_path} && dbt test',
    )
    
    # Set dependencies
    dbt_seed >> dbt_run >> dbt_test