package mongodb

import (
	"context"
	"crypto/x509"
	"errors"
	"fmt"
	"github.com/pingcap/go-ycsb/pkg/prop"
	"io/ioutil"
	"log"
	"math/rand"
	"strings"
	"time"

	"github.com/magiconair/properties"
	"github.com/pingcap/go-ycsb/pkg/ycsb"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/x/mongo/driver/connstring"
)

const (
	mongodbUrl      = "mongodb.url"
	mongodbAuthdb   = "mongodb.authdb"
	mongodbUsername = "mongodb.username"
	mongodbPassword = "mongodb.password"

	mongodbUrlDefault      = "mongodb://127.0.0.1:27017/ycsb?w=1"
	mongodbDatabaseDefault = "ycsb"
	mongodbAuthdbDefault   = "admin"
	mongodbTLSSkipVerify   = "mongodb.tls_skip_verify"
	mongodbTLSCAFile       = "mongodb.tls_ca_file"
)

type mongoDB struct {
	cli *mongo.Client
	db  *mongo.Database
}

func (m *mongoDB) Close() error {
	return m.cli.Disconnect(context.Background())
}

func (m *mongoDB) InitThread(ctx context.Context, threadID int, threadCount int) context.Context {
	return ctx
}

func (m *mongoDB) CleanupThread(ctx context.Context) {
}

// Read a document.
func (m *mongoDB) Read(ctx context.Context, table string, key string, fields []string) (map[string][]byte, error) {
	// Definir a projeção para incluir apenas os campos necessários
	projection := bson.M{"_id": false}
	for _, field := range fields {
		projection["objects."+field] = true
		projection["metadata."+field] = true
	}
	opt := &options.FindOneOptions{Projection: projection}

	// Buscar o documento
	var result bson.M
	if err := m.db.Collection(table).FindOne(ctx, bson.M{"_id": key}, opt).Decode(&result); err != nil {
		return nil, fmt.Errorf("Read error: %s", err.Error())
	}

	// Converter o resultado para o formato esperado
	doc := make(map[string][]byte)
	for k, v := range result {
		switch val := v.(type) {
		case []byte:
			doc[k] = val
		case string:
			doc[k] = []byte(val)
		}
	}

	return doc, nil
}

// Scan documents.
func (m *mongoDB) Scan(ctx context.Context, table string, startKey string, count int, fields []string) ([]map[string][]byte, error) {
	// Definir a projeção para incluir apenas os campos necessários
	projection := bson.M{"_id": false}
	for _, field := range fields {
		projection["objects."+field] = true
		projection["metadata."+field] = true
	}
	limit := int64(count)
	opt := &options.FindOptions{Projection: projection, Sort: bson.M{"_id": 1}, Limit: &limit}

	// Buscar documentos
	cursor, err := m.db.Collection(table).Find(ctx, bson.M{"_id": bson.M{"$gte": startKey}}, opt)
	if err != nil {
		return nil, fmt.Errorf("Scan error: %s", err.Error())
	}
	defer cursor.Close(ctx)

	var docs []map[string][]byte
	for cursor.Next(ctx) {
		var result bson.M
		if err := cursor.Decode(&result); err != nil {
			return nil, fmt.Errorf("Decode error: %s", err.Error())
		}
		doc := make(map[string][]byte)
		for k, v := range result {
			switch val := v.(type) {
			case []byte:
				doc[k] = val
			case string:
				doc[k] = []byte(val)
			}
		}
		docs = append(docs, doc)
	}

	return docs, nil
}

// Insert a document.
func (m *mongoDB) Insert(ctx context.Context, table string, key string, values map[string][]byte) error {
    rand.Seed(time.Now().UnixNano())

  
    objects := bson.M{}

    // Loop para gerar 18 objetos, cada um representando uma data diferente
    for i := 0; i < 18; i++ {
        // Gerar uma data para o objeto (por exemplo, decrementando os dias a partir de hoje)
        date := time.Now().AddDate(0, 0, -i).Format("2006-01-02T00:00:00")

        // Gerar os valores das bandas espectrais aleatoriamente
        bandValues := bson.M{
            "green": rand.Intn(900) + 100, 
            "nir":   rand.Intn(900) + 100,
            "red":   rand.Intn(900) + 100,
            "ndvi":  rand.Intn(900) + 100,
        }

        // Adicionar o objeto ao mapa 'objects' usando a data como chave
        objects[date] = bandValues
    }

    // Criar o campo metadata
    metadata := bson.M{
        "location": bson.M{
            "type":        "Point",
            "coordinates": []float64{rand.Float64()*180 - 90, rand.Float64()*360 - 180}, // Coordenadas aleatórias
        },
    }

    // Criar o documento com ObjectId e os campos solicitados
    doc := bson.M{
        "_id":      key,
        "objects":  objects,
        "metadata": metadata,
    }

    // Inserir o documento
    if _, err := m.db.Collection(table).InsertOne(ctx, doc); err != nil {
        return fmt.Errorf("Insert error: %s", err.Error())
    }
    return nil
}

// Update a document.
func (m *mongoDB) Update(ctx context.Context, table string, key string, values map[string][]byte) error {
	update := bson.M{}
	for k, v := range values {
		update["objects."+k] = v
		update["metadata."+k] = v
	}

	res, err := m.db.Collection(table).UpdateOne(ctx, bson.M{"_id": key}, bson.M{"$set": update})
	if err != nil {
		return fmt.Errorf("Update error: %s", err.Error())
	}
	if res.MatchedCount != 1 {
		return fmt.Errorf("Update error: %s not found", key)
	}
	return nil
}

// Delete a document.
func (m *mongoDB) Delete(ctx context.Context, table string, key string) error {
	res, err := m.db.Collection(table).DeleteOne(ctx, bson.M{"_id": key})
	if err != nil {
		return fmt.Errorf("Delete error: %s", err.Error())
	}
	if res.DeletedCount != 1 {
		return fmt.Errorf("Delete error: %s not found", key)
	}
	return nil
}

type normalCreator struct{}

func (c normalCreator) Create(p *properties.Properties) (ycsb.DB, error) {
	uri := p.GetString(mongodbUrl, mongodbUrlDefault)
	authdb := p.GetString(mongodbAuthdb, mongodbAuthdbDefault)
	tlsSkipVerify := p.GetBool(mongodbTLSSkipVerify, false)
	caFile := p.GetString(mongodbTLSCAFile, "")

	connString, err := connstring.Parse(uri)
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cliOpts := options.Client().ApplyURI(uri)
	if cliOpts.TLSConfig != nil {
		if len(connString.Hosts) > 0 {
			servername := strings.Split(connString.Hosts[0], ":")[0]
			log.Printf("using server name for tls: %s\n", servername)
			cliOpts.TLSConfig.ServerName = servername
		}
		if tlsSkipVerify {
			log.Println("skipping tls cert validation")
			cliOpts.TLSConfig.InsecureSkipVerify = true
		}

		if caFile != "" {
			// Load CA cert
			caCert, err := ioutil.ReadFile(caFile)
			if err != nil {
				log.Fatal(err)
			}
			caCertPool := x509.NewCertPool()
			if ok := caCertPool.AppendCertsFromPEM(caCert); !ok {
				log.Fatalf("certifacte %s could not be parsed", caFile)
			}

			cliOpts.TLSConfig.RootCAs = caCertPool
		}
	}
	t := uint64(p.GetInt64(prop.ThreadCount, prop.ThreadCountDefault))
	cliOpts.SetMaxPoolSize(t)
	username, usrExist := p.Get(mongodbUsername)
	password, pwdExist := p.Get(mongodbPassword)
	if usrExist && pwdExist {
		cliOpts.SetAuth(options.Credential{AuthSource: authdb, Username: username, Password: password})
	} else if usrExist {
		return nil, errors.New("mongodb.username is set, but mongodb.password is missing")
	} else if pwdExist {
		return nil, errors.New("mongodb.password is set, but mongodb.username is missing")
	}

	cli, err := mongo.Connect(ctx, cliOpts)
	if err != nil {
		return nil, err
	}
	if err := cli.Ping(ctx, nil); err != nil {
		return nil, err
	}
	// check if auth passed
	if _, err := cli.ListDatabaseNames(ctx, map[string]string{}); err != nil {
		return nil, errors.New("auth failed")
	}

	fmt.Println("Connected to MongoDB!")

	m := &mongoDB{
		cli: cli,
		db:  cli.Database(mongodbDatabaseDefault),
	}
	return m, nil
}

func init() {
	ycsb.RegisterDBCreator("normal", normalCreator{})
}