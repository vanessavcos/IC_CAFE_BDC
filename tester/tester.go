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

type timeSeries struct {
	ID         string    `bson:"_id"`
	Timestamp  time.Time `bson:"timestamp"`
	NIR        float64   `bson:"nir"`
	Green      float64   `bson:"green"`
	Red        float64   `bson:"red"`
	NVDI       float64   `bson:"nvdi"`
	Metafield  Metafield  `bson:"metafield"`
}

type Metafield struct {
	Type        string    `bson:"type"`
	Coordinates []float64 `bson:"coordinates"`
}

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

func (m *mongoDB) Read(ctx context.Context, table string, key string, fields []string) (map[string][]byte, error) {
    // Definir a projeção para incluir apenas os campos necessários
    projection := bson.M{"_id": false}
    for _, field := range fields {
        projection[field] = true
    }
    opt := &options.FindOneOptions{Projection: projection}

    // Buscar o documento
    var result timeSeries
    if err := m.db.Collection(table).FindOne(ctx, bson.M{"_id": key}, opt).Decode(&result); err != nil {
        return nil, fmt.Errorf("Read error: %s", err.Error())
    }

    // Converter o resultado para o formato esperado
    doc := make(map[string][]byte)
    doc["id"] = []byte(result.ID)
    doc["timestamp"] = []byte(result.Timestamp.Format(time.RFC3339))
    doc["nir"] = []byte(fmt.Sprintf("%f", result.NIR))
    doc["green"] = []byte(fmt.Sprintf("%f", result.Green))
    doc["red"] = []byte(fmt.Sprintf("%f", result.Red))
    doc["nvdi"] = []byte(fmt.Sprintf("%f", result.NVDI))
    doc["metafield"] = []byte(fmt.Sprintf(`{"type":"%s","coordinates":%v}`, result.Metafield.Type, result.Metafield.Coordinates))

    return doc, nil
}

// Scan documents.
func (m *mongoDB) Scan(ctx context.Context, table string, startKey string, count int, fields []string) ([]map[string][]byte, error) {
    // Definir a projeção para incluir apenas os campos necessários
    projection := bson.M{"_id": false}
    for _, field := range fields {
        projection[field] = true
    }
    limit := int64(count)
    opt := &options.FindOptions{
        Projection: projection,
        Sort:       bson.M{"_id": 1},
        Limit:      &limit,
    }

    // Buscar documentos
    cursor, err := m.db.Collection(table).Find(ctx, bson.M{"_id": bson.M{"$gte": startKey}}, opt)
    if err != nil {
        return nil, fmt.Errorf("Scan error: %s", err.Error())
    }
    defer cursor.Close(ctx)

    var docs []map[string][]byte
    for cursor.Next(ctx) {
        var result timeSeries
        if err := cursor.Decode(&result); err != nil {
            return nil, fmt.Errorf("Decode error: %s", err.Error())
        }
        doc := make(map[string][]byte)
        doc["id"] = []byte(result.ID)
        doc["timestamp"] = []byte(result.Timestamp.Format(time.RFC3339))
        doc["nir"] = []byte(fmt.Sprintf("%f", result.NIR))
        doc["green"] = []byte(fmt.Sprintf("%f", result.Green))
        doc["red"] = []byte(fmt.Sprintf("%f", result.Red))
        doc["nvdi"] = []byte(fmt.Sprintf("%f", result.NVDI))
        doc["metafield"] = []byte(fmt.Sprintf(`{"type":"%s","coordinates":%v}`, result.Metafield.Type, result.Metafield.Coordinates))

        docs = append(docs, doc)
    }

    return docs, nil
}


func (m *mongoDB) Insert(ctx context.Context, table string, key string, values map[string][]byte) error {
    rand.Seed(time.Now().UnixNano())

    // Criar o documento com valores aleatórios e um timestamp atual
    doc := timeSeries{
        ID:        key,
        Timestamp: time.Now(),
        NIR:       float64(rand.Intn(900) + 100), // Gera um número entre 100 e 999
        Green:     float64(rand.Intn(900) + 100),
        Red:       float64(rand.Intn(900) + 100),
        NVDI:      float64(rand.Intn(900) + 100),
        Metafield: Metafield{
            Type:        "Point",
            Coordinates: []float64{rand.Float64()*180 - 90, rand.Float64()*360 - 180}, // Coordenadas aleatórias
        },
    }

    // Inserir o documento
    if _, err := m.db.Collection(table).InsertOne(ctx, doc); err != nil {
        return fmt.Errorf("Insert error: %s", err.Error())
    }
    return nil
}


func parseFloat(value []byte) float64 {
    var result float64
    fmt.Sscanf(string(value), "%f", &result)
    return result
}

func parseCoordinates(value []byte) []float64 {
    var metafield Metafield
    if err := bson.Unmarshal(value, &metafield); err != nil {
        return nil
    }
    return metafield.Coordinates
}

func (m *mongoDB) Update(ctx context.Context, table string, key string, values map[string][]byte) error {
    update := bson.M{}
    for k, v := range values {
        switch k {
        case "timestamp":
            var timestamp time.Time
            if err := bson.Unmarshal(v, &timestamp); err != nil {
                return fmt.Errorf("Update error: %s", err.Error())
            }
            update["timestamp"] = timestamp
        case "nir", "green", "red", "nvdi":
            var numericValue float64
            if err := bson.Unmarshal(v, &numericValue); err != nil {
                return fmt.Errorf("Update error: %s", err.Error())
            }
            update[k] = numericValue
        case "metafield":
            var metafield Metafield
            if err := bson.Unmarshal(v, &metafield); err != nil {
                return fmt.Errorf("Update error: %s", err.Error())
            }
            update["metafield"] = metafield
        }
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

type testerCreator struct{}

func (c testerCreator) Create(p *properties.Properties) (ycsb.DB, error) {
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

	if _, err := cli.ListDatabaseNames(ctx, map[string]string{}); err != nil {
		return nil, errors.New("auth failed")
	}

	fmt.Println("Connected to MongoDB!")

	// Cria a coleção de séries temporais com o campo timestamp correto
	db := cli.Database("tester")
	tso := options.TimeSeries().SetTimeField("timestamp") // Certifique-se de que o campo seja "timestamp" minúsculo
	opts := options.CreateCollection().SetTimeSeriesOptions(tso)
	if err := db.CreateCollection(ctx, "usertable", opts); err != nil {
		return nil, fmt.Errorf("error creating time series collection: %v", err)
	}

	m := &mongoDB{
		cli: cli,
		db:  db, // Usando o banco de dados "timeSeriesDB"
	}
	return m, nil
}

func init() {
	ycsb.RegisterDBCreator("tester", testerCreator{})
}
