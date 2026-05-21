const express = require('express');
const { createServer } = require('node:http');
const { join } = require('node:path');
const { Server } = require('socket.io');
const os = require('os');
const app = express();
const server = createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
const port = process.env.PORT || 3000;

app.use(express.static(join(__dirname, '../maxiflop-smartphone')));
app.get('/', (req, res) => res.sendFile(join(__dirname, '../maxiflop-smartphone/index.html')));

const gameState = {
	status: "lobby",
	teams: [
		{ name: "Equipe1", players: [] },
		{ name: "Equipe2", players: [] },
		{ name: "Equipe3", players: [] }
	],
	players: {},
	teamScores: { "Equipe1": 0, "Equipe2": 0, "Equipe3": 0 },
	availableMusics: [],
	playerVotes: {},
	gameMode: "NORMAL"
};

let godotHost = null;

// ─── URL PUBLIQUE ────────────────────────────────────────────────────────────
// Sur Render, RENDER_EXTERNAL_URL est injectée automatiquement.
// En local, tu peux définir PUBLIC_URL dans un .env, sinon on utilise localhost.
const publicUrl =
	process.env.RENDER_EXTERNAL_URL ||
	process.env.PUBLIC_URL ||
	`http://localhost:${port}`;

console.log(`\n=== URL PUBLIQUE ===\n${publicUrl}\n===================\n`);
// ─────────────────────────────────────────────────────────────────────────────

// Envoyer le lobby (infos joueurs) à godot
function sendLobbyToGodot() {
	if (!godotHost) return;

	const playersArr = [];
	Object.keys(gameState.players).forEach(id => {
		playersArr.push({
			id: id,
			pseudo: gameState.players[id].pseudo,
			team: gameState.players[id].team
		});
	});

	const teamScores = { ...gameState.teamScores };

	godotHost.emit("lobby_update", {
		players: playersArr,
		teamScores: teamScores,
		publicUrl: publicUrl
	});
}

function envoyerVotesAGodot() {
	if (gameState.status !== "voting") return;

	const choix = {};
	const totalVotes = Object.keys(gameState.playerVotes).length;

	if (totalVotes === 0) {
		io.emit("vote_update", []);
		return;
	}

	Object.values(gameState.playerVotes).forEach(song => {
		choix[song] = (choix[song] || 0) + 1;
	});

	const statsTrie = Object.keys(choix)
		.map(songName => ({
			songName,
			votes: choix[songName],
			percentage: Math.round((choix[songName] / totalVotes) * 100)
		}))
		.sort((a, b) => b.votes - a.votes)
		.slice(0, 3);

	io.emit("vote_update", statsTrie);
}

function envoyerJoueurRestantGodot(id) {
	if (godotHost) godotHost.emit("player_left", { playerId: id });
}

function envoyerLobbyAClients() {
	io.emit('update-lobby', gameState);
}

function verifierEquilibrage() {
	const size = gameState.teams.map(t => t.players.length);
	const nbActives = size.filter(s => s > 0).length;

	if (nbActives < 1) {
		io.emit('error-lancement', 'Il faut au moins 1 joueur pour jouer !');
		return false;
	}

	const max = Math.max(...size);
	const min = Math.min(...size);

	if (max - min > 2) {
		io.emit('desequilibre', gameState.teams);
		return false;
	}

	return true;
}

io.on('connection', (socket) => {
	console.log('user connected :', socket.id);
	socket.emit('update-lobby', gameState);

	socket.on('host_join', () => {
		console.log('Godot Host connecté via Socket.IO.');
		godotHost = socket;

		// L'URL est connue dès le démarrage, on l'envoie immédiatement
		console.log("[Server] Envoi de l'URL publique à l'hôte Godot :", publicUrl);
		godotHost.emit('public_url', { url: publicUrl });

		sendLobbyToGodot();
	});

	socket.on('host_phase', (data) => {
		gameState.gameMode = data.gameMode || "NORMAL";

		if (gameState.status === "voting" && data.phase !== "voting") {
			const choix = {};
			Object.values(gameState.playerVotes).forEach(song => {
				choix[song] = (choix[song] || 0) + 1;
			});

			let winner = "";
			let maxVotes = -1;
			Object.keys(choix).forEach(song => {
				if (choix[song] > maxVotes) {
					maxVotes = choix[song];
					winner = song;
				}
			});
			if (!winner && gameState.availableMusics.length > 0) {
				winner = gameState.availableMusics[Math.floor(Math.random() * gameState.availableMusics.length)];
			}

			io.emit('vote_result', { winner });

		} else if (data.phase === "voting") {
			if (gameState.status !== "voting") {
				gameState.status = "voting";
				gameState.playerVotes = {};
			}
			envoyerVotesAGodot();
		} else if (data.phase === "reveal" || data.phase === "countdown") {
			gameState.status = data.phase;
		} else if (data.phase === "lobby" || data.phase === "ended") {
			gameState.status = "lobby";
			gameState.playerVotes = {};
		}

		io.emit('host_phase', data);
	});

	socket.on('player_eliminated', (data) => {
		if (data.playerId) {
			console.log(`Joueur éliminé : ${data.playerId}`);
			io.to(data.playerId).emit('eliminated', { status: true });
		}
	});

	socket.on('join-game', (pseudo) => {
		gameState.players[socket.id] = { pseudo, team: 'Equipe1', score: 0 };
		envoyerLobbyAClients();
		sendLobbyToGodot();
	});

	envoyerLobbyAClients();

	socket.on('get_lobby', () => {
		if (socket === godotHost) {
			sendLobbyToGodot();
		}
	});

	socket.on('join-team', (teamName) => {
		const player = gameState.players[socket.id];
		const team = gameState.teams.find(t => t.name === teamName);
		if (!player || !team) return;

		if (player.team) {
			const ancienneTeam = gameState.teams.find(t => t.name === player.team);
			if (ancienneTeam) ancienneTeam.players = ancienneTeam.players.filter(id => id !== socket.id);
		}

		player.team = teamName;
		team.players.push(socket.id);
		io.emit('update-lobby', gameState);
		sendLobbyToGodot();
	});

	socket.on('player_input', (data) => {
		if (godotHost) {
			godotHost.emit('player_input', {
				playerId: socket.id,
				color: Number(data.color),
				clientTs: Number(data.clientTs || Date.now()),
				serverTs: Date.now()
			});
		}
	});

	socket.on('feedback', (data) => {
		if (data.playerId) io.to(data.playerId).emit('feedback', data);
	});

	socket.on('scoreboard', (data) => {
		if (data.players) {
			data.players.forEach(p => {
				if (gameState.players[p.id]) {
					gameState.players[p.id].score = p.score;
					gameState.players[p.id].combo = p.combo;
					gameState.players[p.id].perfect_streak = p.perfect_streak;
				}
			});
		}
		if (data.teamScores) {
			Object.assign(gameState.teamScores, data.teamScores);
		}
	});

	socket.on('music_list', (data) => {
		gameState.availableMusics = data.musics || [];
		io.emit('music_list', gameState.availableMusics);
	});

	socket.on('vote', (data) => {
		const songName = data.songName;
		const cleanVote = songName.trim();
		const match = gameState.availableMusics.find(m => m.trim().toLowerCase() === cleanVote.toLowerCase());

		if (match) {
			gameState.playerVotes[socket.id] = match;
			envoyerVotesAGodot();
		} else {
			gameState.playerVotes[socket.id] = songName;
			envoyerVotesAGodot();
		}
	});

	socket.on('disconnect', () => {
		console.log('user disconnected :', socket.id);

		if (godotHost === socket) {
			console.log('Godot Host déconnecté.');
			godotHost = null;
			return;
		}

		const player = gameState.players[socket.id];
		if (!player) return;

		if (player.team) {
			const team = gameState.teams.find(t => t.name === player.team);
			if (team) team.players = team.players.filter(id => id !== socket.id);
		}

		delete gameState.players[socket.id];
		io.emit('update-lobby', gameState);
		envoyerJoueurRestantGodot(socket.id);
		sendLobbyToGodot();
	});
});

server.listen(port, "0.0.0.0", () => {
	console.log(`\nLocal: http://localhost:${port}`);
	console.log("Système :", os.platform(), os.arch());

	const ifaces = os.networkInterfaces();
	for (let dev in ifaces) {
		ifaces[dev].forEach((d) => {
			if (d.family === 'IPv4' && !d.internal) console.log(`Wifi:  http://${d.address}:${port}`);
		});
	}
});
