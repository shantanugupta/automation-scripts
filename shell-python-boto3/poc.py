import psycopg2 #pip3 install psycopg2-binary --no-cache-dir
from sshtunnel import SSHTunnelForwarder
import getpass

DB="postgres"
DB_UserName="<my-username>"
DB_Password="<my-password>"
SOURCE_DB_SERVER="read-replica-testing-shangupta.xyz.ap-southeast-1.rds.amazonaws.com" #postgreSQL server endpoint
DESTINATION_DB_SERVER="read-replica-testing-shangupta-13a.xyz.ap-southeast-1.rds.amazonaws.com" #postgreSQL server endpoint
DB_SERVER_PORT=5432

REMOTE_HOST="10.x.x.x" #bastion host
PORT=22
REMOTE_USERNAME="<username>" #e.g. james.bond
REMOTE_PASSWORD=getpass.getpass()  #if RSA private key is encrypted with password, provide your password
PRIVATE_KEY_FILE="/Users/jamesbond/.ssh/id_rsa"

tunnels=[(SOURCE_DB_SERVER, DB_SERVER_PORT),
           (DESTINATION_DB_SERVER, DB_SERVER_PORT)]
localPorts = [("127.0.0.1", 8886),
              ("127.0.0.1", 8887)]

server = SSHTunnelForwarder((REMOTE_HOST, PORT),
        ssh_username=REMOTE_USERNAME,
        ssh_pkey=PRIVATE_KEY_FILE,
        ssh_private_key_password=REMOTE_PASSWORD,
        # remote_bind_address=(DB_SERVER, DB_SERVER_PORT),
        remote_bind_addresses=tunnels,
        local_bind_addresses=localPorts
        )


server.start()
conn = psycopg2.connect(
    database=DB,
    user=DB_UserName,
    host=server.local_bind_host,
    port=server.local_bind_port,
    password=DB_Password
    )

cur = conn.cursor()
cur.execute("select * from pg_Settings limit 2;")
data = cur.fetchall()
print(data)
server.stop()