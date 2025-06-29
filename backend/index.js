import express from "express";
import cors from "cors";
import dotenv from "dotenv";

const port = process.env.PORT || 6000;

const app = express();

app.use(cors());
app.use(express.json());

app.get("/", (req, res) => {
  res
    .status(200)
    .send({
      msg: "Hello, This is Node js CI CD Devops project with docker and aws ec2",
    });
});

app.get("/hello", (req, res) => {
  res
    .status(200)
    .send({
      msg: "Hello, This is Node js CI CD Devops project with docker and aws ec2",
    });
});

app.listen(port, () => {
  console.log(`Listening on ${port}`);
});
