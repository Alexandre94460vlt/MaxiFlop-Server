const roomInput = document.getElementById("roomInput");
const nameInput = document.getElementById("nameInput");
const statusText = document.getElementById("status");
const teamInfo = document.getElementById("teamInfo");
const scoreText = document.getElementById("scoreText");
const rankText = document.getElementById("rankText");
const feedbackText = document.getElementById("feedback");
const timerDisplay = document.getElementById("timerDisplay");

const screens = {
	login: document.getElementById("login"),
	waiting: document.getElementById("waiting"),
	controller: document.getElementById("controller"),
	vote: document.getElementById("vote"),
	rotate: document.getElementById("rotate"),
	eliminated: document.getElementById("eliminated-screen")
};

const showScreen = (key) => {
	Object.values(screens).forEach((el) => el.classList.add("hidden"));
	screens[key].classList.remove("hidden");
};

// Connexion relative automatique (s'adapte à l'URL Render en cours)
const socket = io();

document.querySelectorAll(".join-team-btn").forEach((btn) => {
	btn.addEventListener("click", () => {
		const teamName = btn.dataset.team;
		validateAndJoin(teamName);
	});
});

function validateAndJoin(teamName) {
	const roomCode = roomInput.value.trim().toUpperCase();
	const name = nameInput.value.trim();

	if (!roomCode || roomCode.length !== 4) {
		statusText.textContent = "Entrez un code salon valide à 4 caractères !";
		return;
	}
	if (!name) {
		statusText.textContent = "Entrez un pseudo d'abord !";
		return;
	}

	statusText.textContent = "Vérification du salon...";

	// On demande au serveur Node si la room Godot existe
	socket.emit("verify-room", roomCode, (response) => {
		if (response.valid) {
			statusText.textContent = "Connexion...";
			localStorage.setItem("maxiflop_name", name);
			localStorage.setItem("maxiflop_team", teamName);
			localStorage.setItem("maxiflop_room", roomCode);

			// Envoi groupé du pseudo ET du code de session requis par le nouveau serveur
			socket.emit("join-game", { pseudo: name, roomCode: roomCode });

			setTimeout(() => {
				socket.emit("join-team", teamName);
				showScreen("waiting");
			}, 100);
		} else {
			statusText.textContent = response.error;
		}
	});
}

socket.on("update-lobby", (gameState) => {
	const teamCounts = {};
	gameState.teams.forEach(t => teamCounts[t.name] = t.players.length || 0);

	document.querySelectorAll(".join-team-btn").forEach((btn) => {
		const targetTeam = btn.dataset.team;
		const counts = { ...teamCounts };
		counts[targetTeam] = (counts[targetTeam] || 0) + 1; // Simulation d'équilibrage
		
		const sizes = Object.values(counts);
		const max = Math.max(...sizes);
		const min = Math.min(...sizes);
		let isValid = (max - min <= 2);
		
		btn.disabled = !isValid;
		if (!isValid) btn.classList.add("disabled");
		else btn.classList.remove("disabled");
	});

	// Gestion du mode Battle Royale
	const mode = gameState.gameMode || gameState.currentMode || "NORMAL";
	const isBR = (mode === "BATTLE_ROYALE");
	document.querySelector(".team-btns").classList.toggle("hidden", isBR);
	
	const title = document.querySelector("#teamSelection p");
	if (title) title.textContent = isBR ? "Prêt pour le massacre ?" : "Choisis ton équipe :";

	const myPlayer = gameState.players[socket.id];
	if (!myPlayer || !myPlayer.team) return;

	if (isBR) {
		teamInfo.textContent = "Tu es prêt pour le massacre !";
		if (!rankText.textContent.includes("ÉLIMINÉ")) {
			rankText.textContent = `Rang ?`;
		}
		rankText.className = "team-br"; 
	} else {
		teamInfo.textContent = `Tu es dans l'${myPlayer.team} !`;
		if (!rankText.textContent.includes("Rang")) {
			rankText.textContent = `Rang ? - ${myPlayer.team}`;
		}
		if (myPlayer.team === "Equipe1") rankText.className = "team-blue";
		else if (myPlayer.team === "Equipe2") rankText.className = "team-red";
		else rankText.className = "team-yellow";
	}
});

// Écoute des phases de la partie, dictées par Godot
socket.on("host_phase", (data) => {
	if (data.phase === "countdown" || data.phase === "reveal") {
		showScreen("rotate");
	} else if (data.phase === "playing") {
		feedbackText.textContent = "GO !";
		document.body.classList.add("playing");
		showScreen("controller");
	} else if (data.phase === "lobby" || data.phase === "ended") {
		document.body.classList.remove("playing");
		showScreen("waiting");
		timerDisplay.textContent = "En attente du lancement par l'écran principal...";
		scoreText.textContent = "0";
		feedbackText.textContent = "Prêt ?";
	} else if (data.phase === "voting") {
		showScreen("vote");
	}
});

socket.on("error-lancement", (msg) => {
	alert("Erreur : " + msg);
	showScreen("login");
});

socket.on("desequilibre", (teams) => {
	alert("Équipes déséquilibrées ! Il faut s'équilibrer pour que la partie puisse démarrer.");
});

socket.on("feedback", (msg) => {
	const sign = msg.points > 0 ? "+" : "";
	feedbackText.textContent = `${msg.result} (${sign}${msg.points})`;
	scoreText.textContent = `${msg.score}`;

	const teamName = localStorage.getItem("maxiflop_team") || "???";
	if (msg.rank) {
		rankText.textContent = `Rang #${msg.rank} - ${teamName}`;
	}

	triggerVibration(msg.result);
});

socket.on("music_list", (musics) => {
	const musicList = document.getElementById("musicList");
	musicList.innerHTML = "";
	musics.forEach((song) => {
		const item = document.createElement("div");
		item.className = "music-item";
		
		let displayName = song;
		if (song.toUpperCase().endsWith("EASY")) {
			item.classList.add("diff-easy");
			displayName = song.substring(0, song.length - 7);
		} else if (song.toUpperCase().endsWith("MEDIUM")) {
			item.classList.add("diff-medium");
			displayName = song.substring(0, song.length - 9);
		} else if (song.toUpperCase().endsWith("HARD")) {
			item.classList.add("diff-hard");
			displayName = song.substring(0, song.length - 7);
		} else if (song.toUpperCase().endsWith("EXTREME")) {
			item.classList.add("diff-extreme");
			displayName = song.substring(0, song.length - 10);
		}
		
		item.textContent = displayName.trim();
		item.onclick = () => {
			document.querySelectorAll(".music-item").forEach(el => el.classList.remove("selected"));
			item.classList.add("selected");
			socket.emit("vote", { songName: song });
		};
		musicList.appendChild(item);
	});
});

socket.on("vote_result", (data) => {
	console.log("Le gagnant est :", data.winner);
});

socket.on("eliminated", (data) => {
	if (data.status) {
		showScreen("eliminated");
		if (navigator.vibrate) navigator.vibrate([100, 50, 100, 50, 300]);
	}
});

// Détections PC / Mobile pour les hints clavier
const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
if (!isTouchDevice) {
	document.body.classList.add("is-pc");
	const btnBlue = document.querySelector('.btn.blue');
	const btnYellow = document.querySelector('.btn.yellow');
	const btnRed = document.querySelector('.btn.red');
	if (btnBlue) btnBlue.innerHTML = '<span class="key-hint">X</span>';
	if (btnYellow) btnYellow.innerHTML = '<span class="key-hint">C</span>';
	if (btnRed) btnRed.innerHTML = '<span class="key-hint">V</span>';
}

document.addEventListener("keydown", (e) => {
	if (screens.controller.classList.contains("hidden")) return;
	if (e.repeat) return;
	
	let color = -1;
	if (e.code === "KeyX") color = 0; // Bleu
	if (e.code === "KeyC") color = 1; // Jaune
	if (e.code === "KeyV") color = 2; // Rouge
	
	if (color !== -1) {
		socket.emit("player_input", {
			color,
			clientTs: Date.now()
		});
		const btn = document.querySelector(`.btn[data-color="${color}"]`);
		if (btn) {
			btn.classList.add("active-hit");
			setTimeout(() => btn.classList.remove("active-hit"), 100);
		}
	}
});

document.querySelectorAll(".btn[data-color]").forEach((btn) => {
	btn.addEventListener("pointerdown", () => {
		if (navigator.vibrate) navigator.vibrate(50); 
		const color = Number(btn.dataset.color);
		socket.emit("player_input", {
			color,
			clientTs: Date.now()
		});
	});
});

const resultStyles = {
	"PERFECT": { bg: "#84FFC9", vibrate: 100, textColor: "#0a2a1a" },
	"GOOD": { bg: "#AAB2FF", vibrate: 60, textColor: "#0a0a2a" },
	"BAD": { bg: "#F0E040", vibrate: 0, textColor: "#1a1800" },
	"MISS": { bg: "#FF7081", vibrate: 0, textColor: "#1a0005" },
};

let flashTimeout = null;
const controllerScreen = document.getElementById("controller");

function triggerVibration(result) {
	const style = resultStyles[result];
	if (!style) return;

	if (navigator.vibrate) {
		navigator.vibrate(style.vibrate);
	}
	if (flashTimeout) clearTimeout(flashTimeout);

	controllerScreen.style.backgroundColor = style.bg;
	controllerScreen.style.transition = "background-color 0ms";

	flashTimeout = setTimeout(() => {
		controllerScreen.style.transition = "background-color 400ms ease-out";
		controllerScreen.style.backgroundColor = "";
	}, result === "PERFECT" ? 180 : 80);
}

// Récupération et reconnexion automatique multisession
const savedName = localStorage.getItem("maxiflop_name");
const savedRoom = localStorage.getItem("maxiflop_room");
if (savedName && savedRoom) {
	nameInput.value = savedName;
	if (roomInput) roomInput.value = savedRoom;

	const savedTeam = localStorage.getItem("maxiflop_team");
	if (savedTeam) {
		socket.emit("join-game", { pseudo: savedName, roomCode: savedRoom });
		setTimeout(() => {
			socket.emit("join-team", savedTeam);
			showScreen("waiting");
		}, 100);
	}
}
